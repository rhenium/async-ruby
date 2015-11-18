$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "async"
require "pp"

class A
  async def a(arg)
    t = puts "#{arg}-#{Thread.current.object_id}"
    y = 123
    c(2 + (await arg(t)), y) + 1
  end
end
A.new.a(123)
