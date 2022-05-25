# IdentityCache
[![Build Status](https://github.com/Shopify/identity_cache/workflows/CI/badge.svg?branch=main)](https://github.com/Shopify/identity_cache/actions?query=branch%3Amain)

Opt in read through ActiveRecord caching used in production and extracted from Shopify. IdentityCache lets you specify how you want to cache your model objects, at the model level, and adds a number of convenience methods for accessing those objects through the cache. Memcached is used as the backend cache store, and the database is only hit when a copy of the object cannot be found in Memcached.

IdentityCache keeps track of the objects that have cached indexes and uses an `after_commit` hook to expire those objects, and any up the tree, when they are changed.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'identity_cache'
gem 'cityhash'        # optional, for faster hashing (C-Ruby only)

gem 'dalli' # To use :mem_cache_store
# alternatively
gem 'memcached_store' # to use the old libmemcached based client
```

And then execute:

    $ bundle


Add the following to all your environment/*.rb files (production/development/test):

### If you use Dalli (recommended)

```ruby
config.identity_cache_store = :mem_cache_store, "mem1.server.com", "mem2.server.com", {
  expires_in: 6.hours.to_i, # in case of network errors when sending a cache invalidation
  failover: false, # avoids more cache consistency issues
}
```

Add an initializer with this code:

```ruby
IdentityCache.cache_backend = ActiveSupport::Cache.lookup_store(*Rails.configuration.identity_cache_store)
```


### If you use Memcached (old client)

```ruby
config.identity_cache_store = :memcached_store,
  Memcached.new(["mem1.server.com"],
    support_cas: true,
    auto_eject_hosts: false,  # avoids more cache consistency issues
  ), { expires_in: 6.hours.to_i } # in case of network errors when sending a cache invalidation
```

Add an initializer with this code:

```ruby
IdentityCache.cache_backend = ActiveSupport::Cache.lookup_store(*Rails.configuration.identity_cache_store)
```

## Usage

### Basic Usage

``` ruby
class Image < ActiveRecord::Base
  include IdentityCache::WithoutPrimaryIndex
end

class Product < ActiveRecord::Base
  include IdentityCache

  has_many :images

  cache_has_many :images, embed: true
end

# Fetch the product by its id using the primary index as well as the embedded images association.
@product = Product.fetch(id)

# Access the loaded images for the Product.
@images = @product.fetch_images
```

Note: You must include the IdentityCache module into the classes where you want to use it.

### Secondary Indexes

IdentityCache lets you lookup records by fields other than `id`. You can have multiple of these indexes with any other combination of fields:

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache
  cache_index :handle, unique: true
  cache_index :vendor, :product_type
end

# Fetch the product from the cache by the index.
# If the object isn't in the cache it is pulled from the db and stored in the cache.
product = Product.fetch_by_handle(handle)

# Fetch multiple products by providing an array of index values.
products = Product.fetch_multi_by_handle(handles)

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
  cache_has_one :featured_image, embed: :id
end

@product.fetch_featured_image
@product.fetch_images
```

To read multiple records in batch use `fetch_multi`.

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache
end

Product.fetch_multi([1, 2])
```

### Embedding Associations

IdentityCache can easily embed objects into the parents' cache entry. This means loading the parent object will also load the association and add it to the cache along with the parent. Subsequent cache requests will load the parent along with the association in one fetch. This can again mean some duplication in the cache if you want to be able to cache objects on their own as well, so it should be done with care. This works with both `cache_has_many` and `cache_has_one` methods.

``` ruby
class Product < ActiveRecord::Base
  include IdentityCache

  has_many :images
  cache_has_many :images, embed: true
end

@product = Product.fetch(id)
@product.fetch_images
```

With this code, on cache miss, the product and its associated images will be loaded from the db. All this data will be stored into the single cache key for the product. Later requests will load the entire blob of data; `@product.fetch_images` will not need to hit the db since the images are loaded with the product from the cache.

### Caching Polymorphic Associations

IdentityCache tries to figure out both sides of an association whenever it can so it can set those up when rebuilding the object from the cache. In some cases this is hard to determine so you can tell IdentityCache what the association should be. This is most often the case when embedding polymorphic associations.

``` ruby
class Metafield < ActiveRecord::Base
  include IdentityCache
  belongs_to :owner, polymorphic: true
  cache_belongs_to :owner
end

class Product < ActiveRecord::Base
  include IdentityCache
  has_many :metafields, as: :owner
  cache_has_many :metafields
end
```

### Caching Attributes

For cases where you may not need the entire object to be cached, just an attribute from record, `cache_attribute` can be used. This will cache the single attribute by the key specified.

``` ruby
class Redirect < ActiveRecord::Base
  cache_attribute :target, by: [:shop_id, :path]
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
_[:embed]_ When true, specifies that the association should be included with the parent when caching. This means the associated objects will be loaded already when the parent is loaded from the cache and will not need to be fetched on their own. When :ids, only the id of the associated records will be included with the parent when caching. Defaults to `:ids`.

Example:
`cache_has_many :metafields, embed: true`

#### cache_has_one

Options:
_[:embed]_ When true, specifies that the association should be included with the parent when caching. This means the associated objects will be loaded already when the parent is loaded from the cache and will not need to be fetched on their own. No other values are currently implemented. When :id, only the id of the associated record will be included with the parent when caching.

Example:
`cache_has_one :configuration, embed: :id`

#### cache_belongs_to

Example:
`cache_belongs_to :shop`

#### cache_attribute

Options:
_[:by]_ Specifies what key(s) you want the attribute cached by. Defaults to :id.

Example:
`cache_attribute :target, by: [:shop_id, :path]`

## Memoized Cache Proxy

Cache reads and writes can be memoized for a block of code to serve duplicate identity cache requests from memory. This can be done for an http request by adding this around filter in your `ApplicationController`.

``` ruby
class ApplicationController < ActionController::Base
  around_filter :identity_cache_memoization

  def identity_cache_memoization(&block)
    IdentityCache.cache.with_memoization(&block)
  end
end
```

## Versioning

Cache keys include a version number by default, specified in `IdentityCache::CACHE_VERSION`. This version number is updated whenever the storage format for cache values is modified. If you modify the cache value format, you must run `rake update_serialization_format` in order to pass the unit tests, and include the modified `test/fixtures/serialized_record` file in your pull request.

## Caveats

A word of warning. If an `after_commit` fails before the cache expiry `after_commit` the cache will not be expired and you will be left with stale data.

Since everything is being marshalled and unmarshalled from Memcached changing Ruby or Rails versions could mean your objects cannot be unmarshalled from Memcached. There are a number of ways to get around this such as namespacing keys when you upgrade or rescuing marshal load errors and treating it as a cache miss. Just something to be aware of if you are using IdentityCache and upgrade Ruby or Rails.

IdentityCache is also very much _opt-in_ by deliberate design. This means IdentityCache does not mess with the way normal Rails associations work, and including it in a model won't change any clients of that model until you switch them to use `fetch` instead of `find`. This is because there is no way IdentityCache is ever going to be 100% consistent. Processes die, exceptions happen, and network blips occur, which means there is a chance that some database transaction might commit but the corresponding memcached cache invalidation operation does not make it. This means that you need to think carefully about when you use `fetch` and when you use `find`. For example, at Shopify, we never use any `fetch`ers on the path which moves money around, because IdentityCache could simply be wrong, and we want to charge people the right amount of money. We do however use the fetchers on performance critical paths where absolute correctness isn't the most important thing, and this is what IdentityCache is intended for.

## Notes

- See CHANGELOG.md for a list of changes to the library over time.
- The library is MIT licensed and we welcome contributions. See CONTRIBUTING.md for more information.
