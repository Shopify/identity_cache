module IdentityCache
  class CacheFetcher
    attr_accessor :cache_backend

    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value, expires_in: nil, unless_exist: false)
      return if IdentityCache.should_fill_cache?
      @cache_backend.write(key, encode(value), raw: true, expires_in: expires_in, unless_exist: unless_exist)
    end

    def delete(key)
      write(key, IdentityCache::DELETED, expires_in: IdentityCache::DELETED_TTL.seconds)
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
      @cache_backend.cas(key, raw: true) do |data|
        yielded = true
        value = decode(data)
        unless IdentityCache::DELETED == value
          result = value
          break
        end
        result = yield
        break unless IdentityCache.should_fill_cache?
        encode(result)
      end
      unless yielded
        result = yield
        add(key, encode(result))
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

    def cas_multi(keys)
      result = nil
      @cache_backend.cas_multi(*keys, raw: true) do |results|
        results.transform_values! { |data| decode(data) }
        deleted = results.select {|_, v| IdentityCache::DELETED == v }
        results.reject! {|_, v| IdentityCache::DELETED == v }

        result = results
        updates = {}
        missed_keys = keys - results.keys
        unless missed_keys.empty?
          missed_vals = yield missed_keys
          missed_keys.zip(missed_vals) do |k, v|
            result[k] = v
            if deleted.include?(k)
              updates[k] = encode(v)
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
      result.each {|k, v| add(k, v) }
    end

    def add(key, value)
      write(key, value, unless_exist: true)
    end
  end
end
