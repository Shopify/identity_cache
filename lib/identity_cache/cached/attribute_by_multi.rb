# frozen_string_literal: true

module IdentityCache
  module Cached
    class AttributeByMulti < Attribute
      def build
        cached_attribute = self

        model.define_singleton_method(:"fetch_#{fetch_method_suffix}") do |*keys|
          raise_if_scoped
          cached_attribute.fetch(keys)
        end

        model.define_singleton_method(:"fetch_multi_#{fetch_method_suffix}") do |keys|
          raise_if_scoped
          cached_attribute.fetch_multi(keys)
        end
      end

      private

      # Attribute method overrides

      def cast_db_key(keys)
        field_types.each_with_index do |type, i|
          keys[i] = type.cast(keys[i])
        end
        keys
      end

      def unhashed_values_cache_key_string(keys)
        keys.map { |v| v.try!(:to_s).inspect }.join("/")
      end

      def load_from_db_where_conditions(keys)
        Hash[key_fields.zip(keys)]
      end

      def load_multi_rows(keys)
        query = begin
          conditions = keys.map do |keys|
            key_fields.each_with_object({}).with_index do |(field, conds), i|
              conds[field] = keys[i]
            end
          end

          unsorted_model = model.reorder(nil)
          conditions.reduce(nil) do |query, condition|
            if query.nil?
              unsorted_model.where(condition)
            else
              query.or(unsorted_model.where(condition))
            end
          end
        end

        fields = key_fields.dup
        fields.delete(attribute)
        attribute_index = key_fields.index(attribute)

        query.pluck(attribute, *fields).map do |attribute, *key_values|
          index = if attribute_index.nil?
            key_values
          else
            key_values.insert(attribute_index, attribute)
          end
          [index, attribute]
        end
      end

      alias_method :cache_key_from_key_values, :cache_key
    end
  end
end
