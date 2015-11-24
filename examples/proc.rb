$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "async"
require "pp"


class A
  def initialize
    @mutex = Mutex.new
    @seq = 0
  end

  def log(m, s = "")
    method_name = caller.first.split("`").last.chop
    @mutex.synchronize {
      @seq += 1
      puts "%03d %010x [%s] % 40s: %d: %s" % [@seq, Thread.current.object_id, Time.now.strftime("%Y/%m/%d %H:%M:%S.%L"), method_name, m, s]
    }
    [m, s]
  end

  async def a(arg)
    await Async::Task.new { sleep 1 }
    (1..arg).map( &async { |n|
      log n, :before
      log n, arg.to_s
      await Async::Task.new { sleep n.to_f/10 }
      log n, :after
    }).map(&:wait)
  end
end

A.new.a(2)
A.new.a(3)
