require "async/version"
require "async/task"
require "async/ext"
require "pp"

module Async
  def self.transform(array)
    # TODO: is really the await?
    await_index = array[13].index { |ins|
      ins.is_a?(Array) &&
        (ins[0] == :opt_send_without_block || ins[0] == :send) &&
        ins[1][:mid] == :await
    }

    transform_(array, await_index) if await_index

    await_index
  end

  def self.transform_(ary, ai)
    line_number = ary[13].take(ai).reverse.find { |i| i.is_a?(Fixnum) }

    inner_end_i = ary[13].rindex { |i| i.is_a?(Array) && i != [:trace, 16] && i != [:trace, 512] && i != [:leave] }
    inner_body = ary[13].slice!(ai..inner_end_i)
    inner_body.shift(1) # remove send :await

    inner_ctable = []
    ary[12].reject! { |cc| # [type, iseq?, start, end, cont, sp]
      if cc[2..4].all? { |c| inner_body.include?(c) }
        inner_ctable << cc
      elsif cc[2..4].any? { |c| inner_body.include?(c) }
        raise SyntaxError, "async currently doesn't support catching across await-kw"
      end
    }

    inner = [
      *ary.take(4),
      { arg_size: 1, local_size: 2, stack_max: ary[4][:stack_max] }, # 正確に計算するのはめんどい
      "await in #{ary[5]}",
      ary[6], # file name
      ary[7], # file path
      line_number, # line number
      :block,
      [:"#{"await_result"}"], # param
      { lead_num: 1 },
      inner_ctable,
      [
        line_number,
        [:trace, 256], # RUBY_EVENT_B_CALL
        *inner_body,
        [:trace, 512], # RUBY_EVENT_B_RETURN
        [:leave],
      ]
    ]

    fixlocal(inner, 0)
    inner[13].insert(2, [:getlocal_OP__WC__0, 2]) # block param

    transform(inner) # next await in same level

    #    ... self task -> swap
    # -> ... task self -> pop
    # -> ... task -> send
    # -> ...
    ary[13].insert(ai, [:swap], [:pop], [:send, { mid: :continue_with, flag: 4, orig_argc: 0 }, false, inner])
  end

  def self.fixlocal(ary, level)
    # body
    fixlocal_(ary, level)
    # catch
    ary[12].each { |cc| # catch iseq
      fixlocal_(cc[1], level) if cc[1]
    }
    # sub iseq in body
    ary[13].each { |ins|
      next unless ins.is_a?(Array)
      iseq = case ins[0]
             when :send, :invokesuper
               ins[3]
             when :putiseq
               ins[1]
             when :once
               # mupp(ins[1], level + 1) # わからん
             when :defineclass
               # mupp(ins[2], level + 1) # わからん
             end
      fixlocal(iseq, level + 1) if iseq
    }
  end

  def self.fixlocal_(ary, level)
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
