# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require File.expand_path("../lib/identity_cache/version", __FILE__)

Gem::Specification.new do |gem|
  gem.authors = [
    "Camilo Lopez",
    "Tom Burns",
    "Harry Brundage",
    "Dylan Thacker-Smith",
    "Tobias Lutke",
    "Arthur Neves",
    "Francis Bogsanyi",
  ]
  gem.email         = ["gems@shopify.com"]
  gem.description   = "Opt-in read through Active Record caching."
  gem.summary       = "IdentityCache lets you specify how you want to cache your " \
    "model objects, at the model level, and adds a number of " \
    "convenience methods for accessing those objects through " \
    "the cache. Memcached is used as the backend cache store, " \
    "and the database is only hit when a copy of the object " \
    "cannot be found in Memcached."
  gem.homepage      = "https://github.com/Shopify/identity_cache"

  gem.files         = Dir.chdir(File.expand_path(__dir__)) do
    %x(git ls-files -z).split("\x0").reject { |f| f.match(%r{^test/}) }
  end
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.name          = "identity_cache"
  gem.require_paths = ["lib"]
  gem.version       = IdentityCache::VERSION

  gem.required_ruby_version = ">= 3.0.0"

  gem.metadata["allowed_push_host"] = "https://rubygems.org"

  gem.add_dependency("activerecord", ">= 7.0")
  gem.add_dependency("ar_transaction_changes", "~> 1.1")

  gem.add_development_dependency("minitest", "~> 5.14")
  gem.add_development_dependency("mocha", "~> 2.0")
  gem.add_development_dependency("rake", "~> 13.0")
  gem.add_development_dependency("spy", "~> 1.0")
end
