# IdentityCache
[![Build Status](https://api.travis-ci.org/Shopify/identity_cache.png?branch=master)](http://travis-ci.org/Shopify/identity_cache)

Opt in read through ActiveRecord caching used in production and extracted from Shopify. IdentityCache lets you specify how you want to cache your model objects, at the model level, and adds a number of convenience methods for accessing those objects through the cache. Memcached is used as the backend cache store, and the database is only hit when a copy of the object cannot be found in Memcached.

IdentityCache keeps track of the objects that have cached indexes and uses an `after_commit` hook to expire those objects, and any up the tree, when they are changed.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'identity_cache'
```

And then execute:

    $ bundle

Add the following to your environment/production.rb:

```ruby
config.identity_cache_store = :mem_cache_store, Memcached::Rails.new(:servers => ["mem1.server.com"])
```

## Usage

### Basic Usage

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache

  has_many :images

  cache_has_many :images, :embed => true
end

# Fetch the product by its id, the primary index.
@product = Product.fetch(id)

# Fetch the images for the Product. Images are embedded so the product fetch would have already loaded them.
@images = @product.fetch_images
```

Note: You must include the IdentityCache module into the classes where you want to use it.

### Secondary Indexes

IdentifyCache lets you lookup records by fields other than `id`. You can have multiple of these indexes with any other combination of fields:

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache
  cache_index :handle, :unique => true
  cache_index :vendor, :product_type
end

# Fetch the product from the cache by the index.
# If the object isn't in the cache it is pulled from the db and stored in the cache.
product = Product.fetch_by_handle(handle)

products = Product.fetch_by_vendor_and_product_type(vendor, product_type)
```

This gives you a lot of freedom to use your objects the way you want to, and doesn't get in your way. This does keep an independent cache copy in Memcached so you might want to watch the number of different caches that are being added.


### Reading from the cache

IdentityCache adds `fetch_*` methods to the classes that you mark with cache indexes, based on those indexes. The example below will add a `fetch_by_domain` method to the class.

``` ruby
class Shop < ActiveRecord::Base
  include IdentityCache
  cache_index :domain
end
```

Association caches follow suit and add `fetch_*` methods based on the indexes added for those associations.

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache
  has_many  :images
  has_one   :featured_image

  cache_has_many :images
  cache_has_one :featured_image
end

@product.fetch_featured_image
@product.fetch_images
```

### Embedding Associations

IdentityCache can easily embed objects into the parents' cache entry. This means loading the parent object will also load the association and add it to the cache along with the parent. Subsequent cache requests will load the parent along with the association in one fetch. This can again mean some duplication in the cache if you want to be able to cache objects on their own as well, so it should be done with care. This works with both `cache_has_many` and `cache_has_one` methods.

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache

  has_many :images
  cache_has_many :images, :embed => true
end

@product = Product.fetch(id)
@product.fetch_images
```

With this code, on cache miss, the product and its associated images will be loaded from the db. All this data will be stored into the single cache key for the product. Later requests will load the entire blob of data; `@product.fetch_images` will not need to hit the db since the images are loaded with the product from the cache.

### Caching Polymorphic Associations

IdentityCache tries to figure out both sides of an association whenever it can so it can set those up when rebuilding the object from the cache. In some cases this is hard to determine so you can tell IdentityCache what the association should be. This is most often the case when embedding polymorphic associations. The `inverse_name` option on `cache_has_many` and `cache_has_one` lets you specify the inverse name of the association.

``` ruby
class Metafield < ActiveRecord::Base
  belongs_to :owner, :polymorphic => true
end

class Product < ActiveRecord::Base
  include IdentityCache
  has_many :metafields, :as => 'owner'
  cache_has_many :metafields, :inverse_name => :owner
end
```

The `:inverse_name => :owner` option tells IdentityCache what the association on the other side is named so that it can correctly set the assocation when loading the metafields from the cache.


### Caching Attributes

For cases where you may not need the entire object to be cached, just an attribute from record, `cache_attribute` can be used. This will cache the single attribute by the key specified.

``` ruby
class Redirect < ActiveRecord::Base
  cache_attribute :target, :by => [:shop_id, :path]
end

Redirect.fetch_target_by_shop_id_and_path(shop_id, path)
```

This will read the attribute from the cache or query the database for the attribute and store it in the cache.


## Methods Added to ActiveRecord::Base

#### cache_index

Options:  
_[:unique]_ Allows you to say that an index is unique (only one object stored at the index) or not unique, which allows there to be multiple objects matching the index key. The default value is false.

Example:  
`cache_index :handle`

#### cache_has_many

Options:  
_[:embed]_ Specifies that the association should be included with the parent when caching. This means the associated objects will be loaded already when the parent is loaded from the cache and will not need to be fetched on their own.

_[:inverse_name]_ Specifies the name of parent object used by the association. This is useful for polymorphic associations when the association is often named something different between the parent and child objects.

Example:  
`cache_has_many :metafields, :inverse_name => :owner, :embed => true`

#### cache_has_one

Options:  
_[:embed]_ Specifies that the association should be included with the parent when caching. This means the associated objects will be loaded already when the parent is loaded from the cache and will not need to be fetched on their own.

_[:inverse_name]_ Specifies the name of parent object used by the association. This is useful for polymorphic associations when the association is often named something different between the parent and child objects.

Example:
`cache_has_one :configuration, :embed => true`

#### cache_attribute

Options:  
_[:by]_ Specifies what key(s) you want the attribute cached by. Defaults to :id.

Example:  
`cache_attribute :target, :by => [:shop_id, :path]`

## Memoized Cache Proxy

Cache reads and writes can be memoized for a block of code to serve duplicate identity cache requests from memory. This can be done for an http request by adding this around filter in your `ApplicationController`.

``` ruby
class ApplicationController < ActionController::Base
  around_filter :identity_cache_memoization

  def identity_cache_memoization
    IdentityCache.cache.with_memoization{ yield }
  end
end
```

## Caveats

A word of warning. Some versions of rails will silently rescue all exceptions in `after_commit` hooks. If an `after_commit` fails before the cache expiry `after_commit` the cache will not be expired and you will be left with stale data.

Since everything is being marshalled and unmarshalled from Memcached changing Ruby or Rails versions could mean your objects cannot be unmarshalled from Memcached. There are a number of ways to get around this such as namespacing keys when you upgrade or rescuing marshal load errors and treating it as a cache miss. Just something to be aware of if you are using IdentityCache and upgrade Ruby or Rails.

## Contributing

Caching is hard. Chances are that if some feature was left out, it was left out on purpose because it didn't make sense to cache in that way. This is used in production at Shopify so we are very opinionated about the types of features we're going to add. Please start the discussion early, before even adding code, so that we can talk about the feature you are proposing and decide if it makes sense in IdentityCache.

Types of contributions we are looking for:

- Bug fixes
- Performance improvements
- Documentation and/or clearer interfaces

### How To Contribute

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Contributors

Camilo Lopez (@camilo)  
Tom Burns (@boourns)  
Harry Brundage (@hornairs)  
Dylan Smith (@dylanahsmith)  
Tobias Lütke (@tobi)  
John Duff (@jduff)
