guard :rake, task: :compile do
  watch(%r{^ext/.*})
end

guard :minitest do
  watch(%r{^lib/(.*/)?([^/]+)\.rb$}) { |m| ["test/#{m[1]}test_#{m[2]}.rb", "test/#{m[1]}#{m[2]}"] }
  watch(%r{^test/.*\.rb}) { "test" }
end
