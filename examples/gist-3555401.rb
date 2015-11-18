# gist: https://gist.github.com/seraphy/3555401#file-asynctest-cs の AsyncTest.cs を書きかえたもの

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "async"

class Example
  def initialize
    @seq = 0
    @mutex = Mutex.new
  end

  def run
    log 1
    complex = complex_async
    log 2

    fin = complex.continue_with { |result|
      log 3, "result=#{result}"
    }

    log 4
    fin.wait
    log 5
  end

  async def complex_async
    log 1
    job1 = simple_job("JOB1", 2)
    sleep 0.01

    log 2
    job2 = simple_job("JOB2", 5)
    sleep 0.01
    log 3

    ret1 = await job1
    log 4

    job3 = simple_job("JOB3", 2)
    sleep 0.01
    log 5

    ret2 = await job2
    log 6

    @mutex.synchronize { puts "job3=#{job3.completed?}" }
    ret3 = await job3
    log 7

    ret = ret1 + ret2 + ret3
    log 8, "ret=#{ret}"
    ret
  end

  def simple_job(name, mx)
    log 1, name
    Async::Task.new {
      res = 0
      mx.times { |i|
        log 2, name + "/idx=" + i.to_s
        sleep 1
        res += i
      }
      log 3, name + "/res=" + res.to_s
      res
    }
  end

  def log(m, s = "")
    method_name = caller.first.split("`").last.chop
    @mutex.synchronize {
      @seq += 1
      puts "%03d %010x [%s] % 40s: %d: %s" % [@seq, Thread.current.object_id, Time.now.strftime("%Y/%m/%d %H:%M:%S.%L"), method_name, m, s]
    }
  end
end

Example.new.run
