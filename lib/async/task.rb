require "forwardable"

module Async
  class Task
    def initialize(*args, &blk)
      if blk
        @completed = false
        @value = self
        @__next = nil
        @thread = Thread.new(*args) { |*args|
          begin
            yield *args
          ensure
            @completed = true
          end
        }
      else
        @completed = true
        @value = args.first
      end
    end

    def wait
      result
      self
    end

    def result
      return @value if @value != self
      val = @thread.value
      val = val.result if val.is_a?(Task)
      @value = val
    end

    def continue_with
      Task.new {
        yield wait
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
          ret = yield self
          while @__next
            res, @__next = @__next, nil
            ret = yield res
          end
          ret
        }
      end
    end

    def __next__(task)
      @__next = SubTask.new(task, self)
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

  class SubTask
    extend Forwardable

    def_delegators :@task, *(Task.instance_methods - Object.instance_methods - [:__next__])

    def initialize(task, parent)
      @task = task
      @parent = parent
    end

    def __next__(task)
      @parent.__next__(task)
    end
  end
end
