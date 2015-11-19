module Async
  class Task
    def initialize(*args, &blk)
      @completed = false
      @exception = nil
      @value = nil
      @thread = Thread.new(*args) { |*args|
        begin
          yield *args
        ensure
          @completed = true
        end
      }
    end

    def wait
      result
      self
    end

    def result
      return @value if @value
      val = @thread.value
      val = val.result if val.is_a?(Task)
      @value = val
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
