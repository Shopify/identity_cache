module IdentityCache
  class CacheFetcher
    attr_accessor :cache_backend

    def initialize(cache_backend = nil)
      @cache_backend = cache_backend || Rails.cache
    end

    def write(key, value)
      @cache_backend.write(key, value)
    end

    def delete(key)
      @cache_backend.write(key, IdentityCache::DELETED, :expires_in => IdentityCache::DELETED_TTL.seconds)
    end

    def clear
      @cache_backend.clear
    end

    def fetch_multi(keys)
      results = cas_multi(keys) {|missed_keys| yield missed_keys }
      results = add_multi(keys) {|missed_keys| yield missed_keys } if results.nil?
      results
    end

    def fetch(key)
      result = nil
      @cache_backend.cas(key) do |value|
        unless IdentityCache::DELETED == value
          result = value
          break
        end
        result = yield
      end
      if result.nil?
        result = yield
        add(key, result)
      end
      result
    end

    private

    def cas_multi(keys)
      result = nil
      @cache_backend.cas_multi(*keys) do |results|
        deleted = results.select {|_, v| IdentityCache::DELETED == v }
        results.reject! {|_, v| IdentityCache::DELETED == v }

        result = results
        updates = {}
        missed_keys = keys - results.keys
        unless missed_keys.empty?
          missed_vals = yield missed_keys
          missed_keys.zip(missed_vals) do |k, v|
            if v.nil?
              # do nothing
            elsif deleted.include?(k)
              updates[k] = v
            else
              result[k] = v
              add(k, v)
            end
          end
          result.merge!(updates)
        end

        break if updates.empty?
        updates
      end
      result
    end

    def add_multi(keys)
      result = {}
      values = yield keys
      keys.zip(values) do |k, v|
        unless v.nil?
          result[k] = v
          add(k, v)
        end
      end
      result
    end

    def add(key, value)
      @cache_backend.write(key, value, :unless_exist => true)
    end
  end
end
