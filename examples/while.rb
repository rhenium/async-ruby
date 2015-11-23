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
    begin
      log 2
      await job #if arg.odd?
      log 3
      p arg -= 1
    end while arg > 0
    log 4
    :a
  end

  def a1(arg)
    log 1
    while arg > 0
      log 2
      if arg.odd?
        kk = proc { |res|
          __goto :AA
          while arg > 0
            log 2
            if arg.odd?
              job.__await__ &kk 
              return
            end
            :AA
            log 3
            arg -= 1
          end
          log 4
        }
        job.__await__ &kk
        return
      end
      log 3
      arg -= 1
    end
    log 4
  end

  def job
    Async::Task.new { sleep 1; :c }
  end
end

p A.new.a(5).result
