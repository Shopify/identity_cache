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

      def load_multi_rows(keys)
        model.reorder(nil).where(load_from_db_where_conditions(keys)).pluck(key_field, attribute)
      end

      def cache_key_from_key_values(key_values)
        cache_key(key_values.first)
      end
    end
  end
end
