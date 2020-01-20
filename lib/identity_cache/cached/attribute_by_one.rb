# frozen_string_literal: true

module IdentityCache
  module Cached
    class AttributeByOne < Attribute
      attr_reader :key_field

      def initialize(*)
        super
        @key_field = key_fields.first
      end

      def build
        cached_attribute = self

        model.define_singleton_method(:"fetch_#{fetch_method_suffix}") do |key|
          raise_if_scoped
          cached_attribute.fetch(key)
        end

        model.define_singleton_method(:"fetch_multi_#{fetch_method_suffix}") do |keys|
          raise_if_scoped
          cached_attribute.fetch_multi(keys)
        end
      end

      def fetch_multi(keys)
        keys = keys.map { |key| cast_db_key(key) }

        unless model.should_use_cache?
          return load_multi_from_db(keys)
        end

        unordered_hash = CacheKeyLoader.load_multi(self, keys)

        # Calling `values` on the result is expected to return the values in the same order as their
        # corresponding keys. The fetch_multi_by_#{field_list} generated methods depend on this.
        ordered_hash = {}
        keys.each { |key| ordered_hash[key] = unordered_hash.fetch(key) }
        ordered_hash
      end

      def load_multi_from_db(keys)
        rows = model.reorder(nil).where(load_from_db_where_conditions(keys)).pluck(key_field, attribute)
        result = {}
        default = unique ? nil : []
        keys.each do |index_value|
          result[index_value] = default.try!(:dup)
        end
        if unique
          rows.each do |index_value, attribute_value|
            result[index_value] = attribute_value
          end
        else
          rows.each do |index_value, attribute_value|
            result[index_value] << attribute_value
          end
        end
        result
      end

      def cache_encode(db_value)
        db_value
      end
      alias_method :cache_decode, :cache_encode

      private

      # Attribute method overrides

      def cast_db_key(key)
        field_types.first.cast(key)
      end

      def unhashed_values_cache_key_string(key)
        key.try!(:to_s).inspect
      end

      def load_from_db_where_conditions(key_values)
        { key_field => key_values }
      end

      def cache_key_from_key_values(key_values)
        cache_key(key_values.first)
      end
    end
  end
end
