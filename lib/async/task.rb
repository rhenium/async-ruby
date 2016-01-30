require "forwardable"

module Async
  class Task
    def initialize(*args, &blk)
      if blk
        @__next = nil
        @completed = false
        @end = false
        @value = nil
        @thread_waiting = []
        @thread = Thread.new(args) { |args|
          begin
            yield *args
          ensure
            @end = true
            while th = @thread_waiting.shift
              th.wakeup
            end
          end
        }
      else
        @value = args.first
        @completed = true
      end
    end

    def wait
      result
      self
    end

    def __wait__
      return self if @end
      @thread_waiting << Thread.current
      Thread.stop
      self
    end

    def result
      return @value if completed?
      val = @thread.value
      val = val.result if val.is_a?(Task)
      @completed = true
      @value = val
    end

    def continue_with
      Task.new {
        yield __wait__
      }
    end

    def __await__(&blk)
      if @completed
        ret = yield self
        while @__next
          if @__next.completed?
            res, @__next = @__next, nil
            ret = yield res
          else
            return @__next.__await__(&blk)
          end
        end
        ret
      else
        Task.new {
          ret = yield __wait__
          while @__next
            res, @__next = @__next, nil
            ret = yield res.__wait__
          end
          ret
        }
      end
    end

    def __next__(task)
      @__next = task
    end

    def completed?
      @completed
    end

    class << self
      def wrap(val)
        val.is_a?(Task) ? val : Async::Task.new(val)
      end
    end
  end
end
