module IdentityCache
  module MemCacheStoreCas
    def initialize(*args, **options)
      super
      if options.fetch(:support_cas, false)
        require("dalli/cas/client")
      end
    end

    def reset
      rescue_error_with(false) do
        @data.with do |conn|
          conn.reset
        end
      end
    end

    def cas(key, **options)
      options = merged_options(options)
      key = normalize_key(key, options)

      ActiveSupport::Notifications.instrument("cache_cas.active_support", key: key) do
        rescue_error_with(false) do
          @data.with do |conn|
            conn.cas(key, options[:expires_in], options) do |raw_value|
              entry = deserialize_entry(raw_value)
              value = yield entry.value
              ActiveSupport::Cache::Entry.new(value, options)
            end
          end
        end
      end
    end

    def cas_multi(*keys, **options)
      return false if keys.empty?

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
            unless entry.expired?
              values[normalized_keys[key]] = entry.value
            end
          end

          values = yield values

          values.each do |key, value|
            normalized_key = normalize_key(key, options)
            _, cas = raw_values[normalized_key]
            next unless cas

            @data.with do |conn|
              conn.replace_cas(
                normalized_key,
                ActiveSupport::Cache::Entry.new(value, options),
                cas,
                options[:expires_in],
                options,
              )
            end
          end

          true
        end
      end
    end
  end
end

if defined?(ActiveSupport::Cache::MemCacheStore)
  ActiveSupport::Cache::MemCacheStore.prepend(IdentityCache::MemCacheStoreCas)
end
