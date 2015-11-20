require "async/version"
require "async/task"
require "async/ext"
require "pp"

module Async
  def self.transform(ary, return_task = true)
    ary[13] = transform1(ary, ary[13])

    if return_task
      ary[4][:stack_max] = 2 if ary[4][:stack_max] == 1
      last_i = ary[13].rindex { |i| i.is_a?(Array) && i != [:trace, 16] && i != [:trace, 512] && i != [:leave] }
      ary[13].insert(last_i + 1,
                     [:putnil],
                     [:getconstant, :Async],
                     [:getconstant, :Task],
                     [:swap],
                     [:opt_send_without_block, { mid: :new, flag: 0, orig_argc: 1, blockptr: nil }, false])
    end

    pp ary
  end

  def self.transform1(ary, part, line = 0)
    part.each_with_index { |ins, i|
      case ins
      when Fixnum
        line = ins
      when Symbol
        if ary[12].any? { |type, iseq, st, en, cont, sp|
          [:retry, :redo].include?(type) && st == ins }
          raise NotImplementedError, "while loop?"
        end
      when Array
        case ins[0]
        when :send, :opt_send_without_block
          if ins[1][:mid] == :await
            last_i = part.rindex { |i| i.is_a?(Array) && i != [:trace, 16] && i != [:trace, 512] && i != [:leave] }
            return part.take(i) + wrap_async(ary, part[i + 1..last_i], line) + part.drop(last_i + 1)
          end
        when :branchif, :branchunless
          tmp_i = part.index(ins[1])
          tmp = part[tmp_i - 1] # ラベルが else を示すものなら直前に jump があるはず
          if tmp.is_a?(Array) && tmp[0] == :jump
            end_i = part.index(tmp[1])
            afterif = part.drop(end_i + 1)
            inner_main = transform1(ary, part[i + 1...tmp_i - 1] + afterif, line)
            inner_else = transform1(ary, part[tmp_i + 1...end_i] + afterif, line) # TODO: line may be wrong

            return part.take(i + 1) + inner_main + part[tmp_i, 2] + inner_else + part[end_i, 1]
          else
            end_i = tmp_i
            inner = transform1(ary, part[i + 1...end_i] + part.drop(end_i + 1), line) # TODO: leave?
            return part.take(i + 1) + inner + part.drop(end_i)
          end
        end
      end
    }

    part
  end

  def self.wrap_async(ary, part, line)
    inner_ctable = []
    ary[12].reject! { |cc| # [type, iseq?, start, end, cont, sp]
      if cc[2..4].all? { |c| part.include?(c) }
        inner_ctable << cc
      elsif cc[2..4].any? { |c| part.include?(c) }
        raise SyntaxError, "async currently doesn't support catching across await-kw"
      end
    }

    inner = [
      *ary.take(4),
      { arg_size: 1, local_size: 2, stack_max: ary[4][:stack_max] }, # 正確に計算するのはめんどい
      "await in #{ary[5]}",
      ary[6], # file name
      ary[7], # file path
      line, # line number
      :block,
      [:"#{"await_result"}"], # param
      { lead_num: 1 },
      inner_ctable,
      [
        line,
        [:trace, 256], # RUBY_EVENT_B_CALL
        *part,
        [:trace, 512], # RUBY_EVENT_B_RETURN
        [:leave],
      ]
    ]

    fixlocal(inner, 0)
    inner[13].insert(2,
                     [:getlocal_OP__WC__0, 2],
                     [:opt_send_without_block, { mid: :result, flag: 0, orig_argc: 0 }, false])

    inner = transform(inner, false) # next await in same level

    #    ... self task -> swap
    # -> ... task self -> pop
    # -> ... task -> send
    [
      [:swap],
      [:pop],
      [:send, { mid: :continue_with, flag: 4, orig_argc: 0 }, false, inner],
    ]
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
