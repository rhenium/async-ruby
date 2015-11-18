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
      @thread.value
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
