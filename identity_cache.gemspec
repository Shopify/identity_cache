# -*- encoding: utf-8 -*-
require File.expand_path('../lib/identity_cache/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Camilo Lopez", "Tom Burns", "Harry Brundage", "Dylan Smith", "Tobias Lütke"]
  gem.email         = ["harry.brundage@shopify.com"]
  gem.description   = %q{Opt in read through ActiveRecord caching.}
  gem.summary       = %q{IdentityCache lets you specify how you want to cache your model objects, at the model level, and adds a number of convenience methods for accessing those objects through the cache. Memcached is used as the backend cache store, and the database is only hit when a copy of the object cannot be found in Memcached.}
  gem.homepage      = "https://github.com/Shopify/identity_cache"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "identity_cache"
  gem.require_paths = ["lib"]
  gem.version       = IdentityCache::VERSION


  gem.add_dependency('ar_transaction_changes', '0.0.1')
  gem.add_dependency('activerecord', '3.2.13')
  gem.add_dependency('activesupport', '3.2.13')
  gem.add_dependency('memcache-client', '3.2.13')
  gem.add_dependency('cityhash', '0.6.0')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('mocha')
  gem.add_development_dependency('mysql2')
end
