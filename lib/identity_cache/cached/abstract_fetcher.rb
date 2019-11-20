# frozen_string_literal: true

module IdentityCache
  module Cached
    class AbstractFetcher
      def fetch_multi(input_keys)
        unless should_use_cache?
          result = load_multi_from_db(input_keys)
          if result.size != input_keys.size
            input_keys.each do |key|
              result.fetch(key) { result[key] = default_value }
            end
          end
          return result
        end

        input_to_cache_key_map = {}
        input_keys.each do |input_key|
          input_to_cache_key_map[input_key] = input_key_to_cache_key(input_key)
        end

        cache_keys = input_to_cache_key_map.values
        result = nil
        cache_result = IdentityCache.fetch_multi(cache_keys) do |missing_cache_keys|
          cache_to_input_key_map = input_to_cache_key_map.invert
          missing_input_keys = missing_cache_keys.map do |cache_key|
            cache_to_input_key_map.fetch(cache_key)
          end
          result = load_multi_from_db(missing_input_keys)

          missing_input_keys.map do |input_key|
            db_value = result.fetch(input_key) { default_value }
            cache_key = input_to_cache_key_map.fetch(input_key)
            encode(db_value)
          end
        end
        result ||= {}
        input_to_cache_key_map.each do |input_key, cache_key|
          result[input_key] ||= decode(cache_result.fetch(cache_key))
        end
        result
      end

      UNDEFINED = Object.new

      def fetch(input_key)
        unless should_use_cache?
          return load_from_db(input_key)
        end

        cache_key = input_key_to_cache_key(input_key)

        result_value = UNDEFINED
        cache_value = IdentityCache.fetch(cache_key) do
          result_value = load_from_db(input_key)
          encode(result_value)
        end
        if result_value == UNDEFINED
          result_value = decode(cache_value)
        end
        result_value
      end

      private

      def should_use_cache?
        raise NotImplementedError
      end

      def input_key_to_cache_key(input_key)
        raise NotImplementedError
      end

      def load_multi_from_db(ids)
        raise NotImplementedError
      end

      def load_from_db(id)
        load_multi_from_db([id]).fetch(id) { default_value }
      end

      def default_value
        raise NotImplementedError
      end

      # encode value for serialization
      def encode(value)
        value
      end

      def decode(value)
        value
      end
    end
  end
end
