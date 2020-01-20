# frozen_string_literal: true

module IdentityCache
  module Cached
    class AttributeByMulti < Attribute
      def build
        cached_attribute = self

        model.define_singleton_method(:"fetch_#{fetch_method_suffix}") do |*key_values|
          raise_if_scoped
          cached_attribute.fetch(key_values)
        end
      end

      private

      # Attribute method overrides

      def cast_db_key(key_values)
        field_types.each_with_index do |type, i|
          key_values[i] = type.cast(key_values[i])
        end
        key_values
      end

      def unhashed_values_cache_key_string(key_values)
        key_values.map { |v| v.try!(:to_s).inspect }.join('/')
      end

      def load_from_db_where_conditions(key_values)
        Hash[key_fields.zip(key_values)]
      end

      alias_method :cache_key_from_key_values, :cache_key
    end
  end
end
