# frozen_string_literal: true

module IdentityCache
  module LoadStrategy
    module Eager
      extend self

      def load(cache_fetcher, db_key)
        yield CacheKeyLoader.load(cache_fetcher, db_key)
      end

      def load_multi(cache_fetcher, db_keys)
        yield CacheKeyLoader.load_multi(cache_fetcher, db_keys)
      end

      def load_batch(db_keys_by_cache_fetcher)
        yield CacheKeyLoader.load_batch(db_keys_by_cache_fetcher)
      end

      def lazy_load
        lazy_loader = Lazy.new
        yield lazy_loader
        lazy_loader.load_now
        nil
      end
    end
  end
end
