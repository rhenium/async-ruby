module Async
  class Task
    def initialize(*args, &blk)
      @thread = Thread.new(*args) { |*args|
        res = yield *args
        @completed = true
        res
      }
      @completed = false
    end

    def wait
      val = @thread.value
      if val.is_a?(Task)
        val.wait
      else
        val
      end
    end

    def continue_with
      Task.new {
        yield wait
      }
    end

    def completed?
      @completed
    end
  end
end
