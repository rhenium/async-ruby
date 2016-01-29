lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "async/version"

Gem::Specification.new do |spec|
  spec.name          = "async"
  spec.version       = Async::VERSION
  spec.authors       = ["rhenium"]
  spec.email         = ["k@rhe.jp"]

  spec.summary       = %q{async..await for Ruby}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/rhenium/async"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x00")
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-rake"
  spec.add_development_dependency "guard-minitest"
end
