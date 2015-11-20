$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "async"
require "pp"

class A
  def log(m, s = "")
    method_name = caller.first.split("`").last.chop
    @seq ||= 0
    @seq += 1
    puts "%03d %010x [%s] % 40s: %d: %s" % [@seq, Thread.current.object_id, Time.now.strftime("%Y/%m/%d %H:%M:%S.%L"), method_name, m, s]
  end

  async def a(arg)
    log 1
    if arg
      log 2
      await job
    end
    log 3
  end

  def job
    Async::Task.new { sleep 1 }
  end
end

A.new.a(true).result
