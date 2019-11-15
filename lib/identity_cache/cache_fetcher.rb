# frozen_string_literal: true
module IdentityCache
  class CacheFetcher
    attr_accessor :cache_backend

    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value)
      @cache_backend.write(key, value) if IdentityCache.should_fill_cache?
    end

    def delete(key)
      @cache_backend.write(key, IdentityCache::DELETED, expires_in: IdentityCache::DELETED_TTL.seconds)
    end

    def clear
      @cache_backend.clear
    end

    def fetch_multi(keys, &block)
      results = cas_multi(keys, &block)
      results = add_multi(keys, &block) if results.nil?
      results
    end

    def fetch(key)
      result = nil
      yielded = false
      @cache_backend.cas(key) do |value|
        yielded = true
        unless IdentityCache::DELETED == value
          result = value
          break
        end
        result = yield
        break unless IdentityCache.should_fill_cache?
        result
      end
      unless yielded
        result = yield
        add(key, result)
      end
      result
    end

    private

    def cas_multi(keys)
      result = nil
      @cache_backend.cas_multi(*keys) do |results|
        deleted = results.select { |_, v| IdentityCache::DELETED == v }
        results.reject! { |_, v| IdentityCache::DELETED == v }

        result = results
        updates = {}
        missed_keys = keys - results.keys
        unless missed_keys.empty?
          missed_vals = yield missed_keys
          missed_keys.zip(missed_vals) do |k, v|
            result[k] = v
            if deleted.include?(k)
              updates[k] = v
            else
              add(k, v)
            end
          end
        end

        break if updates.empty?
        break unless IdentityCache.should_fill_cache?
        updates
      end
      result
    end

    def add_multi(keys)
      values = yield keys
      result = Hash[keys.zip(values)]
      result.each { |k, v| add(k, v) }
    end

    def add(key, value)
      @cache_backend.write(key, value, unless_exist: true) if IdentityCache.should_fill_cache?
    end
  end
end
