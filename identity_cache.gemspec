# -*- encoding: utf-8 -*-
require File.expand_path('../lib/identity_cache/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Camilo Lopez", "Tom Burns", "John Duff"]
  gem.email         = ["john.duff@jadedpixel.com"]
  gem.description   = %q{Opt in read through ActiveRecord caching}
  gem.summary       = %q{Caches ActiveRecord models in memcache}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "identity_cache"
  gem.require_paths = ["lib"]
  gem.version       = IdentityCache::VERSION


  gem.add_dependency('ar_transaction_changes', '0.0.1')
  gem.add_dependency('cityhash', '0.6.0')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('mocha')
  gem.add_development_dependency('mysql2')
end
