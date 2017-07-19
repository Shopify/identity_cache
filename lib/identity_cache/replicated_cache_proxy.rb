# frozen_string_literal: true

module IdentityCache
  class ReplicatedCacheProxy
    def initialize(cache_backend, blob_replication_factor:)
      @cache_backend = cache_backend
      @blob_replication_factor = blob_replication_factor
    end

    def write(key, value)
      keys(key).each do |key|
        cache_backend.write(key, value)
      end
    end

    def delete(key)
      keys(key).each do |key|
        cache_backend.delete(key)
      end
    end

    def fetch(key)
      cache_backend.fetch(keys(key).sample)
    end

    def fetch_multi(*keys)
      result = {}
      cache_backend.fetch_multi(*keys.map { |key| keys(key).sample }).each do |k, v|
        result[k[0...-2]] = v
      end
      result
    end

    def clear
      cache_backend.clear
    end

    private

    attr_reader(:cache_backend, :blob_replication_factor)

    def keys(key)
      blob_replication_factor.times.map { |i| "#{key}:#{i}" }
    end
  end
end
