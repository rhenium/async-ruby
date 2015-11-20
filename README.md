# async: async..await for Ruby

## これなに
Ruby で C# の async..await ライクなものを実現したいなあ

Ruby ではソースコードや構文木を取り出すことができない（よね？）ので、メソッド・Proc 内部の `rb_iseq_t` を無理矢理書き換えることでなんとかしています。コンパイルには Ruby 2.3.0-preview1 のソースコードが必要です。

今のところ、制御構文は if..else..end のみ使えます。

## コンパイル
```sh
bundle install
ln -sf /path/to/ruby/v2.3.0-preview1/source ext/ruby
rake compile # => lib/async/ext.so
```

## つかいかた

```ruby
require "async" # Module#async が生えます

class A
  async def aaa(arg)
    a1 = bbb(1)
    a2 = bbb(2)

    p b1 = await a1

    if arg
      p b2 = await a2
    else
      p b2 = await bbb(3)
    end

    b1 + b2
  end

  def bbb(arg)
    Async::Task.new {
      sleep arg
      arg
    }
  end
end

p cont = A.new.aaa(true).continue_with { |task|
  task.result * 3
}

p cont.result

# =>
# [00:00] #<Async::Task...
# [00:01] 1
# [00:02] 2
# [00:02] 9

```

## License
MIT License
