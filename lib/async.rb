require "async/version"
require "async/ext"
require "pp"

class AsyncTask
  def initialize(*args, &blk)
    @thread = Thread.new(*args) { |*args|
      res = yield *args
      @completed = true
      res
    }
    @completed = false
  end

  def wait
    @thread.value
  end

  def continue_with
    AsyncTask.new {
      yield wait
    }
  end

  def completed?
    @completed
  end
end

module Kernel
  def await(task)
    task.wait
  end

  def __async_task(task)
    task.continue_with { |res|
      yield res
    }
  end
end

module Async
  def self.transform(array)
    await_index = array[13].index { |ins|
      ins.is_a?(Array) &&
        (ins[0] == :opt_send_without_block || ins[0] == :send) &&
        ins[1][:mid] == :await
    }
    unless await_index
      return pp array
    end

    uniuni(array, await_index)
    pp array
  end

  def self.uniuni(ary, ai)
    unopt(ary)

    inner_tmp = ary[13].slice!(ai...(ary[13].rindex([:trace, 16]) || ary[13].rindex([:leave])))
    inner_tmp.shift(1) # send

    # catch table
    inner_ctable = []
    ary[12].map! { |cc| # [type, iseq?, start, end, cont, sp]
      next cc unless cc[2..4].any? { |c| inner_tmp.include?(c) }
      unless cc[2..4].all? { |c| inner_tmp.include?(c) }
        raise SyntaxError, "async currently doesn't support catching across await-kw"
      end
      inner_ctable << cc
      nil
    }.compact!
    line_number = ary[13].take(ai).reverse.find { |i| i.is_a?(Fixnum) }
    inner =
      [
        *ary.take(4),
        {:arg_size=>1, :local_size=>2, :stack_max=>ary[4][:stack_max]},
        "await in #{ary[5]}", # pos text
        ary[6], # file name
        ary[7], # file path
        line_number, # line number
        :block,
        [:"#{"await_data"}"],
        {:lead_num=>1, :ambiguous_param0=>true},
        inner_ctable,
        [
          line_number,
          [:trace, 256],
          *inner_tmp,
          [:trace, 512],
          [:leave],
        ]
      ]

    mupp(inner, 0)
    inner[13].insert(2, [:getlocal_OP__WC__0, 2]) # block param
    ary[13].insert(ai, [:send, { mid: :__async_task, flag: 4, orig_argc: 1}, false, inner])
  end

  def self.mupp(ary, level)
    # body
    mup(ary, level)
    # catch
    ary[12].each { |cc| # catch iseq
      mup(cc[1], level) if cc[1]
    }
    # sub iseq in body
    ary[13].each { |ins|
      next unless ins.is_a?(Array)
      case ins[0]
      when :send, :invokesuper
        mupp(ins[3], level + 1) if ins[3]
      when :putiseq
        mupp(ins[1], level + 1)
      when :once
        # mupp(ins[1], level + 1) # わからん
      when :defineclass
        # mupp(ins[2], level + 1) # わからん
      end
    }
  end

  def self.mup(ary, level)
    unopt(ary)
    ary[13].map! { |ins|
      if ins.is_a?(Array) && [:setlocal, :getlocal].include?(ins[0]) && ins[2] >= level
        ins[2] += 1
      end
      ins
    }
  end

  def self.unopt(ary)
    ary[13].map! { |ins|
      next ins unless ins.is_a?(Array)
      case ins[0]
      when :setlocal_OP__WC__0
        [:setlocal, ins[1], 0]
      when :setlocal_OP__WC__1
        [:setlocal, ins[1], 1]
      when :getlocal_OP__WC__0
        [:getlocal, ins[1], 0]
      when :getlocal_OP__WC__1
        [:getlocal, ins[1], 1]
      else
        ins
      end
    }
  end
end
