require "async/version"
require "async/task"
require "async/ext"
require "pp"

module Async
  def self.transform(ary)
    pp ary
    new_ary = transform1(duplicate_ary(ary))

    new_ary[4][:stack_max] = 2 if new_ary[4][:stack_max] == 1
    last_i = new_ary[13].rindex { |i| i.is_a?(Array) && i != [:trace, 16] && i != [:trace, 512] && i != [:leave] }
    new_ary[13].insert(last_i + 1,
                       [:putnil],
                       [:getconstant, :Async],
                       [:getconstant, :Task],
                       [:swap],
                       [:opt_send_without_block, { mid: :wrap, flag: 0, orig_argc: 1, blockptr: nil }, false])

    pp new_ary
  end

  def self.duplicate_ary(ary)
    ary.map { |item|
      if item.is_a?(Array)
        duplicate_ary(item)
      elsif item.is_a?(Hash)
        duplicate_ary(item).to_h
      else
        item
      end
    }
  end

  def self.transform1(ary)
    ary[12].each { |cc|
      cc[1] = transform(cc[1]) if cc[1]
    }
    
    await_i = ary[13].index { |ins|
      ins.is_a?(Array) &&
        (ins[0] == :send || ins[0] == :opt_send_without_block) &&
        ins[1][:mid] == :await &&
        ins[1][:orig_argc] == 1 } # TODO

    if await_i
      wrap_await(ary, await_i)
    end

    ary
  end

  def self.wrap_await(ary, await_i)
    line = ary[13].take(await_i).reverse.find { |i| i.is_a?(Fixnum) }

    ary[4][:local_size] += 1
    #ary[10] << :__await__proc
    val_id = ary[10].size + 2

    inner = [
      *ary.take(4),
      { arg_size: 1, local_size: 2, stack_max: ary[4][:stack_max] },
      "await in #{ary[5]}",
      ary[6], # file name
      ary[7], # file path
      line, # line number
      :block,
      [:await_result], # これってなんかいみあるん？
      { lead_num: 1 },
      ary[12],
      [
        line,
        [:trace, 256], # RUBY_EVENT_B_CALL
        [:jump, :"label_after_await_#{await_i}"],
        *ary[13].take(await_i),
        :"label_after_await_#{await_i}",
        *ary[13].drop(await_i + 1),
        [:trace, 512], # RUBY_EVENT_B_RETURN
        [:leave],
      ]
    ]

    inner = fixlocal(inner, 0)
    inner[13].insert(4 + await_i,
                     [:getlocal_OP__WC__0, 2])
    inner[13].insert(3 + await_i,
        [:swap],
        [:pop],
        [:getlocal_OP__WC__1, val_id],
        [:send, { mid: :__await__, flag: 6, orig_argc: 0 }, false, nil],
        [:trace, 512],
        [:leave])

    transform1(inner) # next await in same level

    #    ... self task -> swap
    # -> ... task self -> pop
    # -> ... task -> send
    ary[13][await_i, 1] = 
    [
      [:swap],
      [:pop],
      [:putself],
      [:send, { mid: :lambda, flag: 4, orig_argc: 0 }, false, inner],
      [:setlocal_OP__WC__0, val_id],
      [:getlocal_OP__WC__0, val_id],
      [:send, { mid: :__await__, flag: 6, orig_argc: 0 }, false, nil],
      [:trace, ary[9] == :block ? 512 : 16],
      [:leave],
    ]
  end

  def self.fixlocal(ary, level)
    ary = duplicate_ary(ary)
    # body
    fixlocal_(ary, level)
    # catch
    ary[12].each { |cc| # catch iseq
      next unless cc[1]
      cc[1] = fixlocal(cc[1], level + 1)
    }
    # sub iseq in body
    ary[13].each { |ins|
      next unless ins.is_a?(Array)
      case ins[0]
      when :send, :invokesuper
        ins[3] = fixlocal(ins[3], level + 1) if ins[3]
      when :putiseq
        ins[1] = fixlocal(ins[1], level + 1) if ins[1]
      else # :once, :defineclass わからん
      end
    }

    ary
  end

  def self.fixlocal_(ary, level)
    ary[13].map! { |ins|
      next ins unless ins.is_a?(Array)
      case ins[0]
      when :setlocal_OP__WC__0
        ins = [:setlocal_OP__WC__1, ins[1]] if level <= 0
      when :setlocal_OP__WC__1
        ins = [:setlocal, ins[1], 2] if level <= 1
      when :setlocal
        ins = [:setlocal, ins[1], ins[2] + 1] if level <= ins[2]
      when :getlocal_OP__WC__0
        ins = [:getlocal_OP__WC__1, ins[1]] if level <= 0
      when :getlocal_OP__WC__1
        ins = [:getlocal, ins[1], 2] if level <= 1
      when :getlocal
        ins = [:getlocal, ins[1], ins[2] + 1] if level <= ins[2]
      end
      ins
    }
  end
end
