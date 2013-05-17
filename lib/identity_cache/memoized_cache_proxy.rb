require 'monitor'

module IdentityCache
  class MemoizedCacheProxy
    attr_writer :memcache

    def initialize(memcache = nil)
      @memcache = memcache || Rails.cache
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
      if memoizing?
        hash = {}
        mkv = memoized_key_values
        keys.each do |key|
          hash[key] = mkv[key] if mkv.has_key?(key)
        end
        missing_keys = keys - hash.keys
        hash.merge(@memcache.read_multi(*missing_keys))
      else
        @memcache.read_multi(*keys)
      end
    end

    def clear
      clear_memoization
      @memcache.clear
    end

    private

    def clear_memoization
      @key_value_maps.delete(Thread.current.object_id)
    end

    def memoizing?
      Thread.current[:memoizing_idc]
    end
  end
end
