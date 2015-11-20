# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "pacer/version"

Gem::Specification.new do |s|
  s.name = "pacer"
  s.version = Pacer::VERSION
  s.platform = 'java'
  s.authors = ["Darrick Wiebe"]
  s.email = "dw@xnlogic.com"
  s.homepage = "http://github.com/pangloss/pacer"
  s.license = "MIT"
  s.summary = %Q{A very efficient and easy to use graph traversal engine.}
  s.description = %Q{Pacer defines composeable routes through a graph and then traverses them very quickly.}

  s.files = `git ls-files`.split("\n") + ['lib/pacer-ext.jar']
  s.test_files = `git ls-files -- spec/*`.split("\n")
  s.require_paths = ['lib']
  s.add_dependency "lock_jar", "~> 0.14.4"
  s.add_development_dependency 'xn_gem_release_tasks'
  s.add_development_dependency "rake-compiler",  "~> 0.9.2"
end
