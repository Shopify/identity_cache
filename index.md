---
layout: index
---

# IdentityCache
[![Build Status](https://travis-ci.org/Shopify/identity_cache.svg?branch=master)](https://travis-ci.org/Shopify/identity_cache)

Opt in read through ActiveRecord caching used in production and extracted from Shopify. IdentityCache lets you specify how you want to cache your model objects, at the model level, and adds a number of convenience methods for accessing those objects through the cache. Memcached is used as the backend cache store, and the database is only hit when a copy of the object cannot be found in Memcached.

IdentityCache keeps track of the objects that have cached indexes and uses an 'after_commit' hook to expire those objects, and any up the tree, when they are changed.

## Installation

Add this line to your application's Gemfile:

  ruby
  gem 'identity_cache'
  gem 'cityhash'        # optional, for faster hashing (C-Ruby only)

And then execute:

$ bundle