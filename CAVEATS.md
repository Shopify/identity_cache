While IdentityCache allows to massively scale access to ActiveRecord objects, it's important to note what problems might arise with it over time and what are things that it's not solving in the current design.

## Large blobs

For [god objects](https://en.wikipedia.org/wiki/God_object) (like the Shop model at Shopify), it’s typical to have many associations. It’s appealing for developers to embed many of those associations into the god model’s IDC blob, such as `cache_has_many :images, embed: true`. As a side effect, over time, the god model’s IDC blob may grow very large. It gets even worse when some of the embedded records get larger themselves, and the total IDC blob gets into as much as a megabyte in size. This puts pressure on both the application, memcached, and the network fibre because this large blob needs to be serialized and unserialized each time and transferred over the network.

If the cache blob gets larger than the maximum cache value in memcached, then the cache fill would always fail, causing it to have to load all that data from the database each time.

### Overfetching

There's currently no way to retrieve/fill the cache with a subset of a model's associations. So, for models with many embedded associations, every `Model.fetch` would result in fetching all of the blob over the network and unserializing all embedded records, even if the client has only accessed one of those associations. That's a lot of useless CPU cycles and IO operations that happen on each access. It will also increase the network and memory bandwidth used on both the client and the server.

Another possible issue is that cache invalidations for a model can be amplified by the number of models that embed them. This can further aggravate the large cache blob problem by embedding an association that gets invalidated more frequently.

## Hot keys

To scale out memcache, it’s typical to arrange memcached instances in rings. Most memcache clients/proxies use [consistent hashing](https://github.com/facebook/mcrouter/wiki/Pools#hash-functions) to route the operation to one of the instances in the ring. This means that an IDC entry will always end up in the same memcached instance.

If the key associated with a record is on a hot codepath, that memcached instance will possibly experience saturation on the network and the number of bytes that it can send out. In cloud environments, this is a limit that is easy to hit. This especially aggravates the server-side large blob problem.

## Thundering herd

When a record gets updated, its IDC entry in memcache is expired, and it only gets populated the next time it is accessed. When many clients request the same key concurrently (e.g. on a hot codepath), they all find out that the IDC entry is missing at the same, and hence they will all go to the database to fill the IDC key at the same time. The massive number of clients hitting the DB will create a [thundering herd problem](https://en.wikipedia.org/wiki/Thundering_herd_problem) and overload the DB.

Check out https://github.com/Shopify/identity_cache/pull/373 for more context and for the proposed solution for this problem.
