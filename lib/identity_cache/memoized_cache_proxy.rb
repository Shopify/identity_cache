require 'monitor'

module IdentityCache
  class MemoizedCacheProxy
    attr_accessor :cache_backend

    def initialize(cache_backend = nil)
      @cache_backend = cache_backend || Rails.cache
      @key_value_maps = Hash.new {|h, k| h[k] = {} }
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
      memoized_key_values[key] = value if memoizing?
      @cache_backend.write(key, value)
    end

    def read(key)
      used_cache_backend = true

      result = if memoizing?
        used_cache_backend = false
        mkv = memoized_key_values

        mkv.fetch(key) do
          used_cache_backend = true
          mkv[key] = @cache_backend.read(key)
        end

      else
        @cache_backend.read(key)
      end

      if result
        IdentityCache.logger.debug { "[IdentityCache] #{ used_cache_backend ? '(cache_backend)'  : '(memoized)'  } cache hit for #{key}" }
      else
        IdentityCache.logger.debug { "[IdentityCache] cache miss for #{key}" }
      end

      result
    end

    def delete(key)
      memoized_key_values.delete(key) if memoizing?
      result = @cache_backend.write(key, IdentityCache::DELETED, :expires_in => IdentityCache::DELETED_TTL.seconds)
      IdentityCache.logger.debug { "[IdentityCache] delete #{ result ? 'recorded'  : 'failed'  } for #{key}" }
      result
    end

    def fetch(key)
      used_cache_backend = true
      missed = false
      value = if memoizing?
        used_cache_backend = false
        memoized_key_values.fetch(key) do
          used_cache_backend = true
          cas(key) do
            missed = true
            yield
          end
        end
      else
        cas(key) do
          missed = true
          yield
        end
      end

      if missed
        IdentityCache.logger.debug { "[IdentityCache] cache miss for #{key}" }
      else
        IdentityCache.logger.debug { "[IdentityCache] #{ used_cache_backend ? '(cache_backend)' : '(memoized)' } cache hit for #{key}" }
      end

      value
    end

    def fetch_multi(*keys)
      memoized_keys, cache_backend_keys = [], [] if IdentityCache.logger.debug?

      result = if memoizing?
        hash = {}
        mkv = memoized_key_values

        missing_keys = keys.reject do |key|
          if mkv.has_key?(key)
            memoized_keys << key if IdentityCache.logger.debug?
            hit = mkv[key]
            hash[key] = hit unless hit.nil?
            true
          end
        end

        unless missing_keys.empty?
          results = cas_multi_or_add(missing_keys) do |missed_keys|
            cache_backend_keys.concat(missing_keys - missed_keys) if IdentityCache.logger.debug?
            yield missed_keys
          end
          hash.merge! results
        end
        hash
      else
        cas_multi_or_add(keys) do |missed_keys|
          cache_backend_keys.concat(keys - missed_keys) if IdentityCache.logger.debug?
          yield missed_keys
        end
      end

      log_multi_result(result, memoized_keys, cache_backend_keys) if IdentityCache.logger.debug?

      result
    end

    def read_multi(*keys)
      memoized_keys, cache_backend_keys = [], [] if IdentityCache.logger.debug?

      result = if memoizing?
        hash = {}
        mkv = memoized_key_values

        missing_keys = keys.reject do |key|
          if mkv.has_key?(key)
            memoized_keys << key if IdentityCache.logger.debug?
            hit = mkv[key]
            hash[key] = hit unless hit.nil?
            true
          end
        end

        hits = missing_keys.empty? ? {} : @cache_backend.read_multi(*missing_keys)

        missing_keys.each do |key|
          hit = hits[key]
          mkv[key] = hit
          unless hit.nil?
            cache_backend_keys << key if IdentityCache.logger.debug?
            hash[key] = hit
          end
        end
        hash
      else
        @cache_backend.read_multi(*keys)
      end

      log_multi_result(result, memoized_keys, cache_backend_keys) if IdentityCache.logger.debug?

      result
    end

    def clear
      clear_memoization
      @cache_backend.clear
    end

    private

    def clear_memoization
      @key_value_maps.delete(Thread.current)
    end

    def memoizing?
      Thread.current[:memoizing_idc]
    end

    def cas_multi_or_add(keys)
      results = cas_multi(keys) {|missed_keys| yield missed_keys }
      results = add_multi(keys) {|missed_keys| yield missed_keys } if results.nil?
      results
    end

    def cas(key)
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
      memoized_key_values[key] = result if memoizing?
      result
    end

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
          resolve_multi(missed_keys, missed_vals) do |k, v|
            if deleted.include?(k)
              updates[k] = v
            else
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
      resolve_multi(keys, values) do |k, v|
        result[k] = v
        add(k, v)
      end
      result
    end

    def add(key, value)
      @cache_backend.write(key, value, :unless_exist => true)
    end

    def resolve_multi(keys, values)
      keys.each {|k| IdentityCache.logger.debug "[IdentityCache] cache miss for #{k} (multi)" } if IdentityCache.logger.debug?
      mkv = memoized_key_values if memoizing?
      keys.zip(values) do |key, value|
        yield key, value unless value.nil?
        mkv[key] = value if memoizing?
      end
    end

    def log_multi_result(result, memoized_keys, cache_backend_keys)
      memoized_keys.each {|k| IdentityCache.logger.debug "[IdentityCache] (memoized) cache hit for #{k} (multi)" }
      cache_backend_keys.each {|k| IdentityCache.logger.debug "[IdentityCache] (cache_backend) cache hit for #{k} (multi)" }
    end
  end
end
