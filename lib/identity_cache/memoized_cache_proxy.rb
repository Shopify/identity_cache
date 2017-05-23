require 'monitor'

module IdentityCache
  class MemoizedCacheProxy
    attr_reader :cache_fetcher

    def initialize(cache_adaptor = nil)
      self.cache_backend = cache_adaptor || Rails.cache
      @key_value_maps = Hash.new {|h, k| h[k] = {} }
    end

    def cache_backend=(cache_adaptor)
      if cache_adaptor.respond_to?(:cas) && cache_adaptor.respond_to?(:cas_multi)
        @cache_fetcher = CacheFetcher.new(cache_adaptor)
      else
        @cache_fetcher = FallbackFetcher.new(cache_adaptor)
      end
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
      memoizing = memoizing?
      ActiveSupport::Notifications.instrument('identity_cache.backend.write', memoizing: memoizing) do
        memoized_key_values[key] = value if memoizing
        @cache_fetcher.write(key, value)
      end
    end

    def delete(key)
      memoizing = memoizing?
      ActiveSupport::Notifications.instrument('identity_cache.backend.delete', memoizing: memoizing) do
        memoized_key_values.delete(key) if memoizing
        result = @cache_fetcher.delete(key)
        IdentityCache.logger.debug {"[IdentityCache] delete #{ result ? 'recorded' : 'failed'  } for #{key}"}
        result
      end
    end

    def fetch(key)
      used_cache_backend = true
      missed = false
      memoizing = memoizing?
      value = ActiveSupport::Notifications.instrument('identity_cache.backend.fetch', { memoizing: memoizing }) do |payload|
        value = if memoizing
          used_cache_backend = false
          memoized_key_values.fetch(key) do
            used_cache_backend = true
            memoized_key_values[key] = @cache_fetcher.fetch(key) do
              missed = true
              yield
            end
          end
        else
          @cache_fetcher.fetch(key) do
            missed = true
            yield
          end
        end
        payload[:memoized] = used_cache_backend ? 0 : 1
        payload[:miss] = missed ? 1 : 0
        payload[:populated] = (missed && value) ? 1 : 0
        value
      end

      if missed
        IdentityCache.logger.debug { "[IdentityCache] cache miss for #{key}" }
      else
        IdentityCache.logger.debug { "[IdentityCache] #{ used_cache_backend ? '(cache_backend)' : '(memoized)' } cache hit for #{key}" }
      end

      value
    end

    def fetch_multi(*keys)
      memoized_keys, missed_keys = [], [] if IdentityCache.logger.debug?

      miss_count = 0
      memoized_count = 0

      memoizing = memoizing?
      result = ActiveSupport::Notifications.instrument('identity_cache.backend.fetch_multi', { memoizing: memoizing }) do |payload|
        result = if memoizing
          hash = {}
          mkv = memoized_key_values

          non_memoized_keys = keys.reject do |key|
            if mkv.has_key?(key)
              memoized_keys << key if IdentityCache.logger.debug?
              hit = mkv[key]
              hash[key] = hit unless hit.nil?
              true
            end
          end

          memoized_count = keys.length - non_memoized_keys.length

          unless non_memoized_keys.empty?
            results = @cache_fetcher.fetch_multi(non_memoized_keys) do |missing_keys|
              miss_count = missing_keys.length
              missed_keys.concat(missing_keys) if IdentityCache.logger.debug?
              yield missing_keys
            end
            mkv.merge! results
            hash.merge! results
          end
          hash
        else
          @cache_fetcher.fetch_multi(keys) do |missing_keys|
            miss_count = missing_keys.length
            missed_keys.concat(missing_keys) if IdentityCache.logger.debug?
            yield missing_keys
          end
        end
        payload[:memoized] = memoized_count
        payload[:miss] = miss_count
        payload[:populated] = miss_count - (keys.length - result.length)
        result
      end

      log_multi_result(memoized_keys, keys - missed_keys - memoized_keys, missed_keys) if IdentityCache.logger.debug?

      result
    end

    def clear
      ActiveSupport::Notifications.instrument('identity_cache.backend.clear') do
        clear_memoization
        @cache_fetcher.clear
      end
    end

    private

    def clear_memoization
      @key_value_maps.delete(Thread.current)
    end

    def memoizing?
      !!Thread.current[:memoizing_idc]
    end

    def log_multi_result(memoized_keys, backend_keys, missed_keys)
      memoized_keys.each {|k| IdentityCache.logger.debug "[IdentityCache] (memoized) cache hit for #{k} (multi)" }
      backend_keys.each {|k| IdentityCache.logger.debug "[IdentityCache] (backend) cache hit for #{k} (multi)" }
      missed_keys.each {|k| IdentityCache.logger.debug "[IdentityCache] cache miss for #{k} (multi)" }
    end
  end
end
