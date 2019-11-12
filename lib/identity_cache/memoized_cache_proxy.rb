# frozen_string_literal: true
require 'monitor'
require 'benchmark'

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
        case cache_adaptor
        when ActiveSupport::Cache::MemoryStore, ActiveSupport::Cache::NullStore
          # no need for CAS support
        else
          warn("[IdentityCache] Missing CAS support in cache backend #{cache_adaptor.class} "\
               "which is needed for cache consistency")
        end
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
      ActiveSupport::Notifications.instrument('cache_write.identity_cache', memoizing: memoizing) do
        memoized_key_values[key] = value if memoizing
        @cache_fetcher.write(key, value)
      end
    end

    def delete(key)
      memoizing = memoizing?
      ActiveSupport::Notifications.instrument('cache_delete.identity_cache', memoizing: memoizing) do
        memoized_key_values.delete(key) if memoizing
        if result = @cache_fetcher.delete(key)
          IdentityCache.logger.debug {"[IdentityCache] delete recorded for #{key}"}
        else
          IdentityCache.logger.error {"[IdentityCache] delete failed for #{key}"}
        end
        result
      end
    end

    def fetch(key)
      memo_misses = 0
      cache_misses = 0

      value = ActiveSupport::Notifications.instrument('cache_fetch.identity_cache') do |payload|
        payload[:resolve_miss_time] = 0.0

        value = fetch_memoized(key) do
          memo_misses = 1
          @cache_fetcher.fetch(key) do
            cache_misses = 1
            instrument_duration(payload, :resolve_miss_time) do
              yield
            end
          end
        end
        set_instrumentation_payload(payload, num_keys: 1, memo_misses: memo_misses, cache_misses: cache_misses)
        value
      end

      if cache_misses > 0
        IdentityCache.logger.debug { "[IdentityCache] cache miss for #{key}" }
      else
        IdentityCache.logger.debug do
          "[IdentityCache] #{ memo_misses > 0 ? '(cache_backend)' : '(memoized)' } cache hit for #{key}"
        end
      end

      value
    end

    def fetch_multi(*keys)
      memo_miss_keys = EMPTY_ARRAY
      cache_miss_keys = EMPTY_ARRAY

      result = ActiveSupport::Notifications.instrument('cache_fetch_multi.identity_cache') do |payload|
        payload[:resolve_miss_time] = 0.0

        result = fetch_multi_memoized(keys) do |non_memoized_keys|
          memo_miss_keys = non_memoized_keys
          @cache_fetcher.fetch_multi(non_memoized_keys) do |missing_keys|
            cache_miss_keys = missing_keys
            instrument_duration(payload, :resolve_miss_time) do
              yield missing_keys
            end
          end
        end

        set_instrumentation_payload(payload, num_keys: keys.length,
          memo_misses: memo_miss_keys.length, cache_misses: cache_miss_keys.length)
        result
      end

      log_multi_result(keys, memo_miss_keys, cache_miss_keys)

      result
    end

    def clear
      ActiveSupport::Notifications.instrument('cache_clear.identity_cache') do
        clear_memoization
        @cache_fetcher.clear
      end
    end

    private

    EMPTY_ARRAY = [].freeze
    private_constant :EMPTY_ARRAY

    def set_instrumentation_payload(payload, num_keys:, memo_misses:, cache_misses:)
      payload[:memoizing] = memoizing?
      payload[:memo_hits] = num_keys - memo_misses
      payload[:cache_hits] = memo_misses - cache_misses
      payload[:cache_misses] = cache_misses
    end

    def fetch_memoized(key)
      return yield unless memoizing?
      if memoized_key_values.key?(key)
        return memoized_key_values[key]
      end
      memoized_key_values[key] = yield
    end

    def fetch_multi_memoized(keys)
      return yield keys unless memoizing?

      result = {}
      missing_keys = keys.reject do |key|
        if memoized_key_values.key?(key)
          result[key] = memoized_key_values[key]
          true
        end
      end

      unless missing_keys.empty?
        block_result = yield missing_keys
        memoized_key_values.merge!(block_result)
        result.merge!(block_result)
      end

      result
    end

    def instrument_duration(payload, key)
      value = nil
      payload[key] += Benchmark.realtime do
        value = yield
      end
      value
    end

    def clear_memoization
      @key_value_maps.delete(Thread.current)
    end

    def memoizing?
      !!Thread.current[:memoizing_idc]
    end

    def log_multi_result(keys, memo_miss_keys, cache_miss_keys)
      IdentityCache.logger.debug do
        memoized_keys = keys - memo_miss_keys
        cache_hit_keys = memo_miss_keys - cache_miss_keys
        missed_keys = cache_miss_keys

        memoized_keys.each {|k| IdentityCache.logger.debug("[IdentityCache] (memoized) cache hit for #{k} (multi)") }
        cache_hit_keys.each {|k| IdentityCache.logger.debug("[IdentityCache] (backend) cache hit for #{k} (multi)") }
        missed_keys.each {|k| IdentityCache.logger.debug("[IdentityCache] cache miss for #{k} (multi)") }
      end
    end
  end
end
