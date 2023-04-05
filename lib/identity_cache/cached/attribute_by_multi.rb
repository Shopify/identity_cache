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
        query = generate_query(keys)
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

      # Helper methods

      def generate_query(keys)
        common_fields, unique_fields = extract_common_and_unique_fields(keys)

        common_query = nil
        common_fields.each do |field, value|
          # Optimization for the case of fields in which the key being searched is
          # always the same.
          # This results in a single "WHERE field = value" statement being produced
          # from a single query.
          common_query ||= unsorted_model
          common_query = common_query.where(field => value)
        end

        conditions = if unique_fields.one?
          # Micro-optimization for the case of a single unique field.
          # This results in a single "WHERE field IN (values)" statement being
          # produced from a single query.
          [unique_fields]
        else
          # More than one unique field, so we need to generate a query for each
          # set of values for each unique field.
          #
          # This results in multiple
          #   "WHERE field = value AND field_2 = value_2 OR ..."
          # statements being produced from an object like
          #   [{ field: value, field_2: value_2 }, ...]
          unique_field_rows = unique_fields.keys
          unique_fields.values.transpose.map do |keys|
            keys.each_with_object({}).with_index do |(key, conds), i|
              conds[unique_field_rows[i]] = key
            end
          end
        end

        unique_query = conditions.reduce(nil) do |query, condition|
          if query.nil?
            unsorted_model.where(condition)
          else
            query.or(unsorted_model.where(condition))
          end
        end

        if common_query
          common_query.merge(unique_query)
        else
          unique_query
        end
      end

      def unsorted_model
        model.reorder(nil)
      end

      def extract_common_and_unique_fields(keys)
        common_fields = {}
        unique_fields = {}

        key_fields.length.times do |i|
          field = key_fields[i]
          field_values = keys.map { |key_values| key_values[i] }
          uniq_field_values = field_values.uniq

          if uniq_field_values.one?
            common_fields[field] = uniq_field_values.first
          else
            unique_fields[field] = field_values
          end
        end

        [common_fields, unique_fields]
      end
    end
  end
end
