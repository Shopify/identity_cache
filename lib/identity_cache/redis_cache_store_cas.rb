# frozen_string_literal: true
module IdentityCache
  module RedisCacheStoreCAS
    def cas(name, options = nil)
      options = merged_options(options)
      key = normalize_key(name, options)

      failsafe :cas do
        redis.with do |c|
          c.cas(key, options[:expires_in].to_i, options) do |raw_value|
            raw = options[:raw] || false
            entry = deserialize_entry(raw_value, raw: raw)
            value = yield entry.value
            entry = ActiveSupport::Cache::Entry.new(value, **options)
            raw ? entry.value.to_s : entry
          end
        end
      end
    end

    def cas_multi(*names, **options)
      return if names.empty?

      options = merged_options(options)
      keys_to_names = names.each_with_object({}) { |name, hash| hash[normalize_key(name, options)] = name }
      keys = keys_to_names.keys
      failsafe :mcas do
        redis.with do |c|
          raw_values = c.get_multi_cas(keys)

          values = {}
          raw_values.each do |key, raw_value|
            raw = options[:raw] || false
            entry = deserialize_entry(raw_value.first, raw: raw)
            values[keys_to_names[key]] = options[:raw] ? entry.value.to_s : entry # unless entry.expired?
          end

          updates = yield values

          # TODO(tb): use `CAS.MSET` here instead of single operations
          updates.each do |name, value|
            key = normalize_key(name, options)
            cas_id = raw_values[key].last
            entry = ActiveSupport::Cache::Entry.new(value, **options)
            payload = options[:raw] ? entry.value.to_s : entry
            c.replace_cas(key, payload, cas_id, options[:expires_in].to_i)
          end
        end
      end
    end
  end
end
