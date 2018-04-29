module IdentityCache
  module MemCacheStoreCas
    def cas(key, **options)
      options = merged_options(options)
      key = normalize_key(key, options)

      ActiveSupport::Notifications.instrument("cache_cas.active_support", key: key) do
        rescue_error_with(false) do
          @data.with do |conn|
            conn.cas(key) do |raw_value|
              entry = deserialize_entry(raw_value)
              value = yield entry.value
              ActiveSupport::Cache::Entry.new(value, options)
            end
          end
        end
      end
    end

    def cas_multi(*keys, **options)
      return if keys.empty?

      options = merged_options(options)
      normalized_keys = keys
        .map { |key| [normalize_key(key, options), key] }
        .to_h

      ActiveSupport::Notifications.instrument("cache_cas_multi.active_support", keys: keys) do
        rescue_error_with(false) do
          values = {}
          raw_values = @data.with do |conn|
            conn.get_multi_cas(*keys)
          end

          raw_values.each do |key, raw_value_and_cas|
            raw_value, _ = raw_value_and_cas
            entry = deserialize_entry(raw_value)
            values[normalized_keys[key]] = entry.value unless entry.expired?
          end

          values = yield values

          values.each do |key, value|
            normalized_key = normalize_key(key, options)
            _, cas = raw_values[normalized_key]
            value = ActiveSupport::Cache::Entry.new(value, options)

            @data.with do |conn|
              if cas
                conn.set_cas(normalized_key, value, cas)
              else
                conn.cas(normalized_key, value)
              end
            end
          end

          true
        end
      end
    end
  end
end

if defined?(ActiveSupport::Cache::MemCacheStore)
  require "dalli/cas/client"
  ActiveSupport::Cache::MemCacheStore.prepend(IdentityCache::MemCacheStoreCas)
end
