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

      # AbstractFetcher method overrides

      def cast_input_key(key_values)
        field_types.zip(key_values).map do |type, value|
          type.cast(value)
        end
      end

      # Attribute method overrides

      def load_from_db_where_conditions(key_values)
        Hash[key_fields.zip(key_values)]
      end

      # helper methods

      def field_types
        @field_types ||= key_fields.map { |field| model.type_for_attribute(field.to_s) }
      end
    end
  end
end
