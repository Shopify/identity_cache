module IdentityCache
  class FallbackFetcher
    attr_accessor :cache_backend

    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value)
      @cache_backend.write(key, encode(value), raw: true) if IdentityCache.should_fill_cache?
    end

    def delete(key)
      @cache_backend.delete(key)
    end

    def clear
      @cache_backend.clear
    end

    def fetch_multi(keys, &block)
      results = @cache_backend.read_multi(*keys, raw: true)
      results.transform_values! { |data| decode(data) }
      missed_keys = keys - results.keys
      unless missed_keys.empty?
        replacement_results = yield missed_keys
        missed_keys.zip(replacement_results) do |key, replacement_result|
          write(key, replacement_result)
          results[key] = replacement_result
        end
      end
      results
    end

    def fetch(key)
      result = @cache_backend.read(key, raw: true)
      if result.nil?
        result = yield
        write(key, result)
      else
        result = decode(result)
      end
      result
    end

    private

    def encode(value)
      IdentityCache.codec.encode(value)
    end

    def decode(data)
      IdentityCache.codec.decode(data)
    end
  end
end
