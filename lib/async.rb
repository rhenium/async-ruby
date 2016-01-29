require "async/version"
require "async/task"
require "async/ext"
require "async/utils"

module Async
  def self.transform(ary)
    new_ary = duplicate_ary(ary)
    new_ary[4][:stack_max] = 2 if new_ary[4][:stack_max] == 1
    wrap_with_task(new_ary)
    new_ary = transform1(new_ary)
  end

  # TODO: jump でスタックが壊れている場合は？
  def self.calc_stack_depth(ary, index)
    ary[13].take(index).inject(0) { |sum, ins|
      next sum unless ins.is_a?(Array)
      sum + stack_increase_size(ins)
    }
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

    stack_depth = calc_stack_depth(ary, await_i) - 2
    ary[10] << :$__await__stack << :$__await__task
    add_local_variables(ary, 2)
    stack_val = 3
    task_val = 2

    inner = [
      *ary.take(4),
      { arg_size: 1, local_size: 2, stack_max: ary[4][:stack_max] },
      "await in #{ary[5]}",
      ary[6], # file name
      ary[7], # file path
      line, # line number
      :block,
      [:$__await_result_task__],
      { lead_num: 1, ambiguous_param0: true },
      ary[12],
      [
        line,
        [:jump, :"label_after_await_#{await_i}"],
        *duplicate_ary(ary[13].take(await_i)),
        :"label_after_await_#{await_i}",
        *duplicate_ary(ary[13].drop(await_i + 1)),
        [:leave],
      ]
    ]

    each_iseq(inner) { |ary, level|
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
    }

    inner[13].insert(3 + await_i,
                     [:getlocal_OP__WC__1, stack_val],
                     [:expandarray, stack_depth, 0], # expand stack
                     [:getlocal_OP__WC__0, 2],
                     [:opt_send_without_block, { mid: :result, flag: 16, orig_argc: 0 }, false])
    inner[13].insert(2 + await_i,
                     [:swap],
                     [:pop],
                     [:reverse, stack_depth + 1],
                     [:newarray, stack_depth],
                     [:setlocal_OP__WC__1, stack_val],
                     [:getlocal_OP__WC__1, task_val],
                     [:swap],
                     [:opt_send_without_block, { mid: :__next__, flag: 16 + 128, orig_argc: 1 }, false],
                     [:leave])

    transform1(inner) # next await in same level

    # depth: 3
    #    a b self task -> setlocal(task_val, 0)
    # -> a b self -> pop
    # -> a b -> reverse(depth)
    # -> b a -> newarray(depth)
    # -> task [ta.b.a] -> send(argc=1)
    # -> new_task
    ary[13][await_i, 1] = [
      [:setlocal_OP__WC__0, task_val],
      [:pop],
      [:reverse, stack_depth],
      [:newarray, stack_depth],
      [:setlocal_OP__WC__0, stack_val],
      [:getlocal_OP__WC__0, task_val],
      [:send, { mid: :__await__, flag: 4 + 128, orig_argc: 0 }, false, inner],
      [:leave],
    ]
  end

  def self.wrap_with_task(ary)
    wrapper = [
      [:putnil],
      [:getconstant, :Async],
      [:getconstant, :Task],
      [:swap],
      [:opt_send_without_block, { mid: :wrap, flag: 128, orig_argc: 1, blockptr: nil }, false]
    ]
    body = ary[13]
    i = body.size - 1
    while i >= 0
      body.insert(i, *wrapper) if body[i] == [:leave]
      i -= 1
    end
  end

  # yields: iseq, level
  def self.each_iseq(ary, level = 0, &blk)
    yield ary, level

    ary[12].each { |cc|
      each_iseq(cc[1], level + 1, &blk) if cc[1] }
    ary[13].each { |ins|
      next unless ins.is_a?(Array)
      case ins[0]
      when :send, :invokesuper
        each_iseq(ins[3], level + 1, &blk) if ins[3]
      when :putiseq
        each_iseq(ins[1], level + 1, &blk) if ins[1]
      else # :once, :defineclass わからん
      end }
  end

  def self.add_local_variables(boss, count)
    each_iseq(boss) { |ary, level|
      ary[13].each { |ins|
        next unless ins.is_a?(Array)
        case ins[0]
        when :setlocal_OP__WC__0, :getlocal_OP__WC__0
          ins[1] += count if level == 0
        when :setlocal_OP__WC__1, :getlocal_OP__WC__1
          ins[1] += count if level == 1
        when :setlocal, :getlocal
          ins[1] += count if level == ins[2]
        end
      }
    }
  end
end
