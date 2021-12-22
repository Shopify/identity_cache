# frozen_string_literal: true
require "dalli/cas/client" unless Dalli::VERSION > "3"

module IdentityCache
  module MemCacheStoreCAS
    def cas(name, options = nil)
      options = merged_options(options)
      key = normalize_key(name, options)

      rescue_error_with(false) do
        instrument(:cas, key, options) do
          @data.with do |connection|
            connection.cas(key, options[:expires_in].to_i, options) do |raw_value|
              entry = deserialize_entry(raw_value, raw: options[:raw])
              value = yield entry.value
              entry = ActiveSupport::Cache::Entry.new(value, **options)
              options[:raw] ? entry.value.to_s : entry
            end
          end
        end
      end
    end

    def cas_multi(*names, **options)
      return if names.empty?

      options = merged_options(options)
      keys_to_names = names.each_with_object({}) { |name, hash| hash[normalize_key(name, options)] = name }
      keys = keys_to_names.keys
      rescue_error_with(false) do
        instrument(:cas_multi, keys, options) do
          raw_values = @data.with { |c| c.get_multi_cas(keys) }

          values = {}
          raw_values.each do |key, raw_value|
            entry = deserialize_entry(raw_value.first, raw: options[:raw])
            values[keys_to_names[key]] = entry.value unless entry.expired?
          end

          updates = yield values

          updates.each do |name, value|
            key = normalize_key(name, options)
            cas_id = raw_values[key].last
            entry = ActiveSupport::Cache::Entry.new(value, **options)
            payload = options[:raw] ? entry.value.to_s : entry
            @data.with { |c| c.replace_cas(key, payload, cas_id, options[:expires_in].to_i, options) }
          end
        end
      end
    end

    if ActiveSupport::Cache::MemCacheStore.instance_method(:deserialize_entry).arity == 1

      private

      def deserialize_entry(payload, raw: nil) # rubocop:disable Lint/UnusedMethodArgument
        super(payload)
      end
    end
  end
end
