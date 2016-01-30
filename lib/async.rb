require "async/version"
require "async/task"
require "async/ext"
require "async/utils"

module Async
  def self.transform(ary)
    inner = transform_inner(ary)
    new_ary = [
      *ary.take(4),
      { arg_size: 1, local_size: ary[4][:local_size] + 3, stack_max: 1 }, # TODO: local_size
      ary[5], # location
      ary[6], # file name
      ary[7], # file path
      ary[8], # line number
      :method,
      (ary[10] << :$__await_jump__ << :$__await_stack__ << :$__await_proc__),
      ary[11],
      [],
      [
        ary[8], # line
        [:putspecialobject, 1],
        [:send, { mid: :lambda, flag: 4, orig_argc: 0 }, false, inner],
        [:dup],
        [:setlocal_OP__WC__0, 2],
        [:putnil],
        [:opt_send_without_block, { mid: :[], flag: 16, orig_argc: 1 }, false],
        [:leave]
      ]
    ]
  end

  def self.transform_inner(ary)
    shift_count = 3

    inner = [
      *ary.take(4),
      { arg_size: 0, local_size: 2, stack_max: ary[4][:stack_max] },
      "await in #{ary[5]}",
      ary[6], # file name
      ary[7], # file path
      ary[8], # line number
      :block,
      [:$__await_result__],
      { lead_num: 1 },
      ary[12].each { |cc| cc[1] && burylocal(cc[1], shift: shift_count, base_level: 1) },
      ary[13]
    ]

    burylocal(inner, shift: shift_count)

    tags = []
    shift_size = 3
    body = inner[13]
    i = body.size - 1
    begin
      ins = body[i]
      next unless ins.is_a?(Array)
      case ins[0]
      when :leave
        body.insert(i,
          [:putnil],
          [:getconstant, :Async],
          [:getconstant, :Task],
          [:swap],
          [:opt_send_without_block, { mid: :wrap, flag: 128, orig_argc: 1, blockptr: nil }, false])
      when :send, :opt_send_without_block
        next unless ins[1][:mid] == :await && ins[1][:orig_argc] == 1 # TODO
        tags << tag = :"@__await_jump_#{i}__"
        stack_depth = calc_stack_depth(body, i) - 2
        # depth: 2
        # -> a b task self -> swap
        # -> a b self task -> pop
        # -> a b task -> reverse(depth)
        # -> task b a -> newarray(depth)
        # -> task [ta.b.a] -> send(argc=1)
        # -> new_task
        body[i, 1] = [
          [:putobject, tag],
          [:setlocal_OP__WC__1, 4],
          [:swap],
          [:pop],
          [:reverse, stack_depth + 1],
          [:newarray, stack_depth],
          [:setlocal_OP__WC__1, 3],
          [:getlocal_OP__WC__1, 2],
          [:send, { mid: :__await__, flag: 2 + 128, orig_argc: 0 }, false, nil],
          [:leave],
          tag,
          [:getlocal_OP__WC__1, 3],
          [:expandarray, stack_depth, 0],
          [:getlocal_OP__WC__0, 2],
          [:opt_send_without_block, { mid: :result, flag: 16, orig_argc: 0 }, false]
        ]
      end
    end while (i -= 1) > 0

    body.insert(0,
      [:getlocal_OP__WC__1, 4],
      [:opt_case_dispatch, tags.flat_map { |t| [t, t] }, :@__await__else__],
      :@__await__else__)

    inner
  end

  def self.burylocal(ary, shift:, base_level: 0)
    shift_count = 3
    each_iseq(ary) { |tary, level|
      next if base_level > level
      tary[13].map! { |ins|
        next ins unless ins.is_a?(Array)
        case ins[0]
        when :setlocal_OP__WC__0
          ins[1] += shift if level == 0
          ins[0] = :setlocal_OP__WC__1 if level == 0
        when :getlocal_OP__WC__0
          ins[1] += shift if level == 0
          ins[0] = :getlocal_OP__WC__1 if level == 0
        when :setlocal_OP__WC__1
          ins[1] += shift if level == 1
          ins.replace([:setlocal, ins[1], 2]) if level <= 1
        when :getlocal_OP__WC__1
          ins[1] += shift if level == 1
          ins.replace([:getlocal, ins[1], 2]) if level <= 1
        when :setlocal, :getlocal
          ins[1] += shift if level == ins[2]
          ins[2] += 1 if level <= ins[2]
        end
        ins
      }
    }
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

  # TODO: jump でスタックが壊れている場合は？
  def self.calc_stack_depth(body, index)
    body.take(index).inject(0) { |sum, ins|
      next sum unless ins.is_a?(Array)
      sum + stack_increase_size(ins)
    }
  end
end
