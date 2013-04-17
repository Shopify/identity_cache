require 'monitor'

module IdentityCache
  class MemoizedCacheProxy
    attr_writer :memcache

    def initialize(memcache = nil)
      @memcache = memcache || config_cache_store || Rails.cache
      @key_value_maps = Hash.new {|h, k| h[k] = {} }
    end

    def memoized_key_values
      @key_value_maps[Thread.current.object_id]
    end

    def with_memoization(&block)
      Thread.current[:memoizing_idc] = true
      yield
    ensure
      clear_memoization
      Thread.current[:memoizing_idc] = false
    end

    def write(key, value)
      memoized_key_values[key] = value if memoizing?
      @memcache.write(key, value)
    end

    def read(key)
      if memoizing?
        memoized_key_values[key] ||= @memcache.read(key)
      else
        @memcache.read(key)
      end
    end

    def delete(key)
      memoized_key_values.delete(key) if memoizing?
      @memcache.delete(key)
    end

    def read_multi(*keys)
      hash = {}

      if memoizing?
        keys.reduce({}) do |hash, key|
          hash[key] = memoized_key_values[key] if memoized_key_values[key].present?
          hash
        end
      end

      missing_keys = keys - hash.keys
      hash.merge(@memcache.read_multi(*missing_keys))
    end

    def clear
      clear_memoization
      @memcache.clear
    end

    private

    def config_cache_store
      rails_config = Rails.configuration
      return unless rails_config.respond_to?(:identity_cache_store)
      ActiveSupport::Cache.lookup_store(rails_config.identity_cache_store)
    end

    def clear_memoization
      @key_value_maps.delete(Thread.current.object_id)
    end

    def memoizing?
      Thread.current[:memoizing_idc]
    end
  end
end
