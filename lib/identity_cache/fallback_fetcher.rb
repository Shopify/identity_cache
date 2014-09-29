module IdentityCache
  class FallbackFetcher
    attr_accessor :cache_backend

    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value)
      @cache_backend.write(key, value) if IdentityCache.should_update_cache?
    end

    def delete(key)
      @cache_backend.delete(key) if IdentityCache.should_update_cache?
    end

    def clear
      @cache_backend.clear if IdentityCache.should_update_cache?
    end

    def exists?(key)
      @cache_backend.exist?(key)
    end

    def read(key)
      @cache_backend.read(key)
    end

    def fetch_multi(keys, &block)
      results = @cache_backend.read_multi(*keys)
      missed_keys = keys - results.keys
      unless missed_keys.empty?
        replacement_results = yield missed_keys
        missed_keys.zip(replacement_results) do |key, replacement_result|
          @cache_backend.write(key, replacement_result) if IdentityCache.should_update_cache?
          results[key] = replacement_result
        end
      end
      results
    end

    def fetch(key)
      result = @cache_backend.read(key)
      if result.nil?
        result = yield
        @cache_backend.write(key, result) if IdentityCache.should_update_cache?
      end
      result
    end
  end
end
