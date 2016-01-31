module Async
  class BaseTask
    def initialize
      @state = :running
      @thread_waiting = Queue.new
      @connects = Queue.new
    end

    def completed?
      @state != :running
    end

    def wait
      result
      self
    end

    def result
      case @state
      when :running
        @thread_waiting << Thread.current
        Thread.stop
        result
      when :finished
        @value
      when :errored
        raise @value
      else
        raise "invalid state"
      end
    end

    def continue_with
      Task.new {
        yield wait
      }
    end

    private
    def wakeup_waiters
      @thread_waiting.close
      @connects.close
      while th = @thread_waiting.pop
        th.wakeup
      end
      while ctask = @connects.pop
        ctask.send(:__continue__, self)
      end
    end

    def __connect__(ctask)
      case @state
      when :running
        @connects << ctask
      when :finished, :errored
        ctask.send(:__continue__, self)
      else
        raise "invalid state"
      end
    end
  end

  class Task < BaseTask
    def initialize(*args)
      raise ArgumentError, "block is required" unless block_given?
      super()
      @thread = Thread.new(args) { |args|
        begin
          @value = yield *args
          @state = :finished
        rescue Exception => e
          @value = e
          @state = :errored
        ensure
          wakeup_waiters
        end
      }
      @thread.abort_on_exception = true
    end
  end

  class CTask < BaseTask
    def initialize(&proc)
      super()
      @proc = proc
    end
    private_class_method :new

    private
    def __next__(task)
      @next = task
    end

    def __continue__(task = nil)
      @next = nil
      ret = @proc[task]
    rescue Exception
      @value = $!
      @state = :errored
      wakeup_waiters
    else
      if @next
        @next.send(:__connect__, self)
      else
        @value = ret
        @state = :finished
        wakeup_waiters
      end
    ensure
      return self
    end
  end
end
