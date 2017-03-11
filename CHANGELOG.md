# IdentityCache changelog

#### 0.6.0 Unreleased

- Raise when trying to cache a belong_to association with a scope. Previously the scope was ignored on a cache hit (#323)
- Remove deprecated `never_set_inverse_association` option (#319)

#### 0.5.1

- Fix bug in prefetch_associations for cache_has_one associations that may be nil

#### 0.5.0

- `never_set_inverse_association` and `fetch_read_only_records` are now `true` by default (#315)
- Store the class name instead of the class itself (#311)

#### 0.4.1

- Deprecated embedded associations on models that don't use IDC (#305)
- Remove a respond_to? check that hides mistakes in includes hash (#307)
- Drop ruby 2.1 support (#301)
- Avoid querying when no ids are passed to fetch_multi (#297)
- Fix fetching already loaded belongs_to association (#294)
- Move `should_use_cache?` calls to the model-level (#291)
- Clone instead of dup record when readonlyifying fetched records (#292)
- Consistently store the array for cached has many associations (#288)

#### 0.4.0

- Return an array from fetched association to prevent chaining. Up to now, a relation was returned by default. (#287)

#### 0.3.2

- Deprecate returning non read-only records when cache is used. Set IdentityCache.fetch_readonly_records to true to avoid this. (#282)
- Use loaded association first when fetching a cache_has_many id embedded association (#280)
- Deprecate setting the inverse active record association on cache hits. Set IdentityCache.never_set_inverse_association to true to avoid this. (#279)
- Fetch association returns relation or array depending on the configuration. It was only returning a relation for cache_has_many fetch association methods. (#276)
- Stop sharing the same attributes hash between the fetched record and the memoized cache, which could interfere with dirty tracking (#267)

#### 0.3.1

- Fix cache_index for non-id primary key

#### 0.3.0

- Add support for includes option on cache_index and fetch_by_id
- Use ActiveRecord instantiate
- Add association pre-fetching support for fetch_by_id
- Remove support for 3.2
- Fix N+1 from fetching embedded ids on a cache miss
- Raise when trying to cache a through association. Previously it wouldn't be invalidated properly.
- Raise if a class method is called on a scope.  Previously the scope was ignored.
- Raise if a class method is called on a subclass of one that included IdentityCache. This never worked properly.
- Fix cache_belongs_to on polymorphic assocations.
- Fetching a cache_belongs_to association no longer loads the belongs_to association

#### 0.2.5

- Fixed support for namespaced model classes
- Added some deduplication for parent cache expiry
- Fixed some deprecation warnings in rails 4.2

#### 0.2.4

- Refactoring, documentation and test changes

#### 0.2.3

- PostgreSQL support
- Rails 4.2 compatibility
- Fix: Don't connect to database when calling `IdentityCache.should_use_cache?`
- Fix: Fix invalid parent cache invalidation if object is embedded in different parents

#### 0.2.2

- Change: memcached is no longer a runtime dependency
- Use cache for read-only models.

#### 0.2.1

- Add a fallback backend using local memory.

#### 0.2.0

- Memcache CAS support

#### 0.1.0

- Backwards incompatible change: Stop expiring cache on after_touch callback.
- Change: fetch_multi accepts an array of keys as argument
- Change: :embed option value from false to :ids for cache_has_many for clarity
- Fix: Consistently use ActiveRecord / Arel APIs to build SQL queries
- Fix: `SystemStackError` when fetching more records than the max stack size
- Fix: Bug in `fetch_multi` in a transaction where results weren't compacted.
- Fix: Avoid unused preload on fetch_multi with :includes option for cache miss
- Fix: reload will invalidate the local instance cache

#### 0.0.7

- Add support for non-integer primary keys
- Fix: Not implemented error for cache_has_one with embed: false
- Fix: cache key to change when adding a cache_has_many association with :embed => false
- Fix: Compatibility rails 4.1 for `quote_value`, which needs default column.

#### 0.0.6

- Fix: bug where previously nil-cached attribute caches weren't expired on record creation
- Fix: cache key to not change when adding a non-embedded association.
- Perf: Rails 4 Only create `CollectionProxy` when using it

#### 0.0.5


#### 0.0.4

- Fix: only marshal attributes, embedded associations and normalized association IDs
- Add cache version number to cache keys
- Add test case to ensure version number is updated when the marshalled format changes

#### 0.0.3

- Fix: memoization for multi hits actually work
- Fix: quotes `SELECT` projection elements on cache misses
- Add CPU performance benchmark
- Fix: table names are not hardcoded anymore
- Logger now differentiates memoized vs non memoized hits

#### 0.0.2

- Fix: Existent embedded entries will no longer raise when `ActiveModel::MissingAttributeError` when accessing a newly created attribute.
- Fix: Do not marshal raw ActiveRecord associations
