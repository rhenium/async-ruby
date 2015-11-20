require "async/version"
require "async/task"
require "async/ext"
require "pp"

module Async
  def self.transform(ary)
    pp ary
    ary[13] = transform1(ary, ary[13])
    pp ary
  end

  def self.find_ins_o(part, offset, size, insns, val = [])
    part[offset, size || part.size].index { |ins|
      ins.is_a?(Array) &&
        insns.include?(ins[0]) &&
        val.each_with_index.all? { |v, i|
          !v ||
            (lv = ins[i + 1]) && (lv.is_a?(Hash) && v.is_a?(Hash) ? lv >= v : lv == v) } }
  end

  def self.transform1(ary, part)
    p begin_if_i = find_ins_o(part, 0, nil, [:branchif, :branchunless])
    p first_await_i = find_ins_o(part, 0, nil, [:send, :opt_send_without_block], [{ mid: :await }])
    end_i = part.rindex { |i| i.is_a?(Array) && i != [:trace, 16] && i != [:trace, 512] && i != [:leave] }

    return part unless first_await_i

    if !begin_if_i || first_await_i < begin_if_i
      part[first_await_i, end_i] = wrap_async(ary, part[first_await_i..end_i])
    else
      end_if_o = part.index(part[begin_if_i][1]) - begin_if_i # label
      await_o = first_await_i - begin_if_i
      # else?
      part[begin_if_i + await_o, end_if_o - await_o] = wrap_async(ary, part[begin_if_i + await_o, end_if_o - await_o] + part[begin_if_i + end_if_o + 1..end_i])
    end

    part
  end

  def self.wrap_async(ary, part)
    line_number = 999 # TODO
    # line_number = ary[13].take(ai).reverse.find { |i| i.is_a?(Fixnum) }

    inner_body = part.drop(1)

    # inner_ctable = []
    # ary[12].reject! { |cc| # [type, iseq?, start, end, cont, sp]
    #   if cc[2..4].all? { |c| inner_body.include?(c) }
    #     inner_ctable << cc
    #   elsif cc[2..4].any? { |c| inner_body.include?(c) }
    #     raise SyntaxError, "async currently doesn't support catching across await-kw"
    #   end
    # }

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
      [], # inner_ctable,
      [
        line_number,
        [:trace, 256], # RUBY_EVENT_B_CALL
        *inner_body,
        [:trace, 512], # RUBY_EVENT_B_RETURN
        [:leave],
      ]
    ]

    fixlocal(inner, 0)
    inner[13].insert(2, [:getlocal_OP__WC__0, 2],
                     [:opt_send_without_block, { mid: :result, flag: 0, orig_argc: 0 }, false])

    # transform(inner) # next await in same level

    #    ... self task -> swap
    # -> ... task self -> pop
    # -> ... task -> send
    # -> ...
    part.insert(0, [:swap], [:pop], [:send, { mid: :continue_with, flag: 4, orig_argc: 0 }, false, inner], [:leave])

    part
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
