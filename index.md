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

Add the following to your environment/production.rb:

    ruby
    config.identity_cache_store = :mem_cache_store, Memcached::Rails.new(:servers => ["mem1.server.com"])

Add an initializer with this code:

    ruby
    IdentityCache.cache_backend = ActiveSupport::Cache.lookup_store(*Rails.configuration.identity_cache_store)

## Usage

### Basic Usage

    ruby
    class Product < ActiveRecord::Base
      include IdentityCache

      has_many :images

      cache_has_many :images, :embed => true
    end

    # Fetch the product by its id, the primary index.
    @product = Product.fetch(id)

    # Fetch the images for the Product. Images are embedded so the product fetch would have already loaded them.
    @images = @product.fetch_images

Note: You must include the IdentityCache module into the classes where you want to use it.

### Secondary Indexes

IdentifyCache lets you lookup records by fields other than 'id'. You can have multiple of these indexes with any other combination of fields:

    ruby
    class Product < ActiveRecord::Base
      include IdentityCache
      cache_index :handle, :unique => true
      cache_index :vendor, :product_type
    end

    # Fetch the product from the cache by the index.
    # If the object isn't in the cache it is pulled from the db and stored in the cache.
    product = Product.fetch_by_handle(handle)

    products = Product.fetch_by_vendor_and_product_type(vendor, product_type)

This gives you a lot of freedom to use your objects the way you want to, and doesn't get in your way. This does keep an independent cache copy in Memcached so you might want to watch the number of different caches that are being added.

