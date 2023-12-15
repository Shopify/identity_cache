# frozen_string_literal: true

module IdentityCache
  class FallbackFetcher
    attr_accessor :cache_backend

    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value)
      @cache_backend.write(key, value) if IdentityCache.should_fill_cache?
    end

    def delete(key)
      @cache_backend.delete(key)
    end

    def clear
      @cache_backend.clear
    end

    def fetch_multi(keys)
      results = if IdentityCache.should_use_cache?
        @cache_backend.read_multi(*keys)
      else
        {}
      end
      missed_keys = keys - results.keys
      unless missed_keys.empty?
        replacement_results = yield missed_keys
        missed_keys.zip(replacement_results) do |key, replacement_result|
          @cache_backend.write(key, replacement_result) if IdentityCache.should_fill_cache?
          results[key] = replacement_result
        end
      end
      results
    end

    def fetch(key, **cache_fetcher_options)
      unless cache_fetcher_options.empty?
        raise ArgumentError, "unsupported cache_fetcher options: #{cache_fetcher_options.keys.join(", ")}"
      end

      result = @cache_backend.read(key)
      if result.nil?
        result = yield
        @cache_backend.write(key, result) if IdentityCache.should_fill_cache?
      end
      result
    end
  end
end
