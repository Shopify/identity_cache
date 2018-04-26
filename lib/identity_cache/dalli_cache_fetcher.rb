module IdentityCache
  class DalliCacheFetcher
    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value)
      @cache_backend.write(key, value) if IdentityCache.should_fill_cache?
    end

    def delete(key)
      @cache_backend.write(
        key,
        IdentityCache::DELETED,
        expires_in: IdentityCache::DELETED_TTL.seconds,
      )
    end

    def clear
      @cache_backend.clear
    end

    def fetch_multi(keys, &block)
      ActiveSupport::Notifications.instrument("cache_cas_multi.active_support", keys: keys) do
        results = @cache_backend.dalli.get_multi_cas(*keys)

        deleted = results.select {|_, (v, _)| IdentityCache::DELETED == v }
        results = results.reject {|_, (v, _)| IdentityCache::DELETED == v }

        missed_keys = keys - results.keys
        unless missed_keys.empty?
          updates, additions = {}, {}

          missed_vals = yield missed_keys
          missed_keys.zip(missed_vals) do |k, v|
            results[k] = [v, nil]
            if deleted.include?(k)
              updates[k] = v
            else
              additions[k] = v
            end
          end

          additions.each { |k, v| add(k, v) }
          updates.each do |k, v|
            _, cas = deleted[k]
            @cache_backend.dalli.set_cas(k, v, cas)
          end if IdentityCache.should_fill_cache?
        end

        results.each_with_object({}) do |(k, v_and_cas), memo|
          v, _ = v_and_cas
          memo[k] = v
        end
      end
    end

    def fetch(key)
      ActiveSupport::Notifications.instrument("cache_cas.active_support", key: key) do
        result = nil
        yielded = false
        @cache_backend.dalli.cas(key) do |value|
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
    end

    private

    def add_multi(keys)
      values = yield(keys)
      keys
        .zip(values)
        .to_h
        .each { |k, v| add(k, v) }
    end

    def add(key, value)
      @cache_backend.write(key, value, unless_exist: true) if IdentityCache.should_fill_cache?
    end
  end
end
