# frozen_string_literal: true

module IdentityCache
  module Cached
    class AttributeByOne < Attribute
      def build
        cached_attribute = self

        model.define_singleton_method(:"fetch_#{fetch_method_suffix}") do |key_value|
          raise_if_scoped
          cached_attribute.fetch(key_value)
        end

        model.define_singleton_method(:"fetch_multi_#{fetch_method_suffix}") do |key_values|
          raise_if_scoped
          cached_attribute.fetch_multi(key_values)
        end
      end

      private

      # AbstractFetcher method overrides

      def cast_input_key(index_key)
        field_type.cast(index_key)
      end

      def input_key_to_cache_key(index_key)
        super([index_key])
      end

      def load_multi_from_db(index_keys)
        field = key_fields.first
        rows = model.reorder(nil).where(field => index_keys).pluck(field, attribute)
        result = {}
        index_keys.each do |index_key|
          result[index_key] = default_value
        end
        if unique
          rows.each do |index_key, attribute_value|
            result[index_key] = attribute_value
          end
        else
          rows.each do |index_key, attribute_value|
            (result[index_key] ||= []) << attribute_value
          end
        end
        result
      end

      # Attribute method overrides

      def load_from_db_where_conditions(index_key)
        { key_fields.first => index_key }
      end

      # helper methods

      def field_type
        @field_type ||= model.type_for_attribute(key_fields.first.to_s)
      end
    end
  end
end
