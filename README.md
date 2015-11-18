# async: async..await for Ruby

## これなに
Ruby で C# の async..await ライクなものを実現したいなあ

現在はメソッド内部の `rb_iseq_t*` を無理矢理書き換えることでなんとかしています。コンパイルには Ruby のソースコードが必要です。

## コンパイル
```sh
bundle install
ln -sf /path/to/ruby/v2.3.0-preview1/source ext/ruby
rake compile # => lib/async/ext.so
```

## つかいかた

```ruby
require "async"

class A
  async def aaa
    a1 = bbb(1)
    a2 = bbb(2)

    p b1 = await a1
    p b2 = await a2
    b1 + b2
  end

  def bbb(arg)
    Async::Task.new {
      sleep arg
      arg
    }
  end
end

p task = A.new.aaa.continue_with { |result|
  result * 3
}

p task.wait

# =>
# [00:00] #<Async::Task...
# [00:01] 1
# [00:02] 2
# [00:02] 9

```

## License
MIT License
