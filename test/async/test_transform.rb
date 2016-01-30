require "test_helper"

class TransformTest < Minitest::Test
  def test_wrap
    klass = Class.new {
      async def t
        123
      end
    }
    task = klass.new.t
    assert task.completed?
    assert_equal(123, task.result)
  end

  def test_simple
    klass = Class.new {
      async def t(q)
        q << 1
        q << await(sleep_async)
        q << 2
      end
      def sleep_async; Async::Task.new { sleep 0.1; :x } end
    }
    a = []
    start = Time.now
    task = klass.new.t(a)
    assert_equal([1], a)
    assert (Time.now - start) < 0.05
    assert !task.completed?
    task.result
    assert_equal([1, :x, 2], a)
    assert task.completed?
    assert (Time.now - start) >= 0.1
    assert (Time.now - start) < 1.05
  end

  def test_two
    klass = Class.new {
      async def t(q)
        q << await(sleep_async) << await(sleep_async)
      end
      def sleep_async; Async::Task.new { sleep 0.1; :x } end
    }
    a = []
    start = Time.now
    task = klass.new.t(a)
    assert_equal([:x, :x], task.result)
    assert (Time.now - start) >= 0.2
    assert (Time.now - start) < 2.05
  end

  def test_two_parallel
    klass = Class.new {
      async def t
        j1 = sleep_async
        j2 = sleep_async
        [[await(j1), await(j2)]].to_h
      end
      def sleep_async; Async::Task.new { sleep 0.1; :x } end }
    start = Time.now
    task = klass.new.t
    assert_equal({ x: :x }, task.result)
    assert (Time.now - start) >= 0.1
    assert (Time.now - start) < 1.05
  end

  def test_two_same
    klass = Class.new {
      async def t
        js = []; q = []
        10.times {
          js << Async::Task.new { sleep 0.01; q << :x } }
        while j = js.shift
          await j end
        q.size end }
    start = Time.now
    task = klass.new.t
    assert_equal(10, task.result)
    assert (Time.now - start) >= 0.01
    assert (Time.now - start) < 0.06
  end

  def test_throw
    klass = Class.new {
      async def t
        raise "uniuni"
      end
    }
    task = klass.new.t
    err = nil
    assert_raises(RuntimeError) {
      begin
        task.result
      rescue Exception => e
        raise err = e end }
    assert_equal("uniuni", err.message)
  end

  def test_await_throw
    klass = Class.new {
      async def t
        await Async::Task.new { raise "uniuni" }
      end
    }
    task = klass.new.t
    err = nil
    assert_raises(RuntimeError) {
      begin
        task.result
      rescue Exception => e
        raise err = e end }
    assert_equal("uniuni", err.message)
  end

  def test_rescued
    klass = Class.new {
      async def t
        raise "uniuni"
      rescue => e
        e.message
      end
    }
    task = klass.new.t
    assert_equal("uniuni", task.result)
  end
end
