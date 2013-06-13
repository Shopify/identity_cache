require 'monitor'
require 'set'

module IdentityCache
  class MemoizedCacheProxy
    attr_accessor :cache_backend

    def initialize(cache_backend = nil)
      @cache_backend = cache_backend || Rails.cache
      @key_value_maps = Hash.new {|h, k| h[k] = {} }
      @deletion_queue = []
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
      @cache_backend.write(key, value)
    end

    def read(key)
      used_cache_backendd = true

      result = if memoizing?
        used_cache_backendd = false
        mkv = memoized_key_values

        mkv.fetch(key) do
          used_cache_backendd = true
          mkv[key] = @cache_backend.read(key)
        end

      else
        @cache_backend.read(key)
      end

      if result
        IdentityCache.logger.debug { "[IdentityCache] #{ used_cache_backendd ? '(cache_backend)'  : '(memoized)'  } cache hit for #{key}" }
      else
        IdentityCache.logger.debug { "[IdentityCache] cache miss for #{key}" }
      end

      result
    end

    def begin_batch
      @batch = true
      @deletion_queue.unshift Set.new
    end

    def end_batch
      @deletion_queue.shift.each do |key|
        @cache_backend.delete(key)
      end
      @batch = (@deletion_queue != [])
    end

    def delete(key)
      memoized_key_values.delete(key) if memoizing?
      if @batch
        @deletion_queue.first << key
      else
        @cache_backend.delete(key)
      end
    end

    def read_multi(*keys)

      if IdentityCache.logger.debug?
        memoized_keys , cache_backend_keys = [], []
      end

      result = if memoizing?
        hash = {}
        mkv = memoized_key_values

        missing_keys = keys.reject do |key|
          if mkv.has_key?(key)
            memoized_keys << key if IdentityCache.logger.debug?
            hit = mkv[key]
            hash[key] = hit unless hit.nil?
            true
          end
        end

        hits =   missing_keys.empty? ? {} : @cache_backend.read_multi(*missing_keys)

        missing_keys.each do |key|
          hit = hits[key]
          mkv[key] = hit
          hash[key] = hit unless hit.nil?
        end
        hash
      else
        @cache_backend.read_multi(*keys)
      end

      if IdentityCache.logger.debug?

        result.each do |k, v|
          cache_backend_keys << k if !v.nil? && !memoized_keys.include?(k)
        end

        memoized_keys.each{ |k| IdentityCache.logger.debug "[IdentityCache] (memoized) cache hit for #{k} (multi)" }
        cache_backend_keys.each{ |k| IdentityCache.logger.debug "[IdentityCache] (cache_backend) cache hit for #{k} (multi)" }
      end

      result
    end

    def clear
      clear_memoization
      @cache_backend.clear
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
