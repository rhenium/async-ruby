require "mkmf"

if defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
  $CFLAGS += " -Wall"
  $CFLAGS += " -I#{File.expand_path("../ruby/", __FILE__)}"
  create_makefile("ext")
end
