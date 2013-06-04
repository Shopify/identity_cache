require 'monitor'

module IdentityCache
  class MemoizedCacheProxy
    attr_writer :memcache

    def initialize(memcache = nil)
      @memcache = memcache || Rails.cache
      @key_value_maps = Hash.new {|h, k| h[k] = {} }
    end

    def memoized_key_values
      @key_value_maps[Thread.current]
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
      used_memcached = true

      result = if memoizing?
        used_memcached = false
        mkv = memoized_key_values

        mkv.fetch(key) do
          used_memcached = true
          mkv[key] = @memcache.read(key)
        end

      else
        @memcache.read(key)
      end

      if result
        IdentityCache.logger.debug { "[IdentityCache] #{ used_memcached ? '(memcache)'  : '(memoized)'  } cache hit for #{key}" }
      else
        IdentityCache.logger.debug { "[IdentityCache] cache miss for #{key}" }
      end

      result
    end

    def delete(key)
      memoized_key_values.delete(key) if memoizing?
      @memcache.delete(key)
    end

    def read_multi(*keys)

      if IdentityCache.logger.debug?
        memoized_keys , memcache_keys = [], []
      end

      result = if memoizing?
        hash = {}
        mkv = memoized_key_values

        missing_keys = keys.reject do |key|
          if mkv.has_key?(key)
            memoized_keys << key if IdentityCache.logger.debug?
            hash[key] = mkv[key]
            true
          end
        end
        hash.merge(@memcache.read_multi(*missing_keys))

      else
        @memcache.read_multi(*keys)
      end

      if IdentityCache.logger.debug?

        result.each do |k, v|
          memcache_keys << k if !v.nil? && !memoized_keys.include?(k)
        end

        memoized_keys.each{ |k| IdentityCache.logger.debug "[IdentityCache] (memoized) cache hit for #{k} (multi)" }
        memcache_keys.each{ |k| IdentityCache.logger.debug "[IdentityCache] (memcache) cache hit for #{k} (multi)" }
      end

      result
    end

    def clear
      clear_memoization
      @memcache.clear
    end

    private

    def clear_memoization
      @key_value_maps.delete(Thread.current)
    end

    def memoizing?
      Thread.current[:memoizing_idc]
    end
  end
end
