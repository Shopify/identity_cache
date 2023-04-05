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
        query = load_multi_rows_query(keys)
        fields = key_fields
        if (attribute_index = key_fields.index(attribute))
          fields = fields.dup
          fields.delete(attribute)
        end

        query.pluck(attribute, *fields).map do |attribute, *key_values|
          key_values.insert(attribute_index, attribute) if attribute_index
          [key_values, attribute]
        end
      end

      alias_method :cache_key_from_key_values, :cache_key

      # Helper methods

      def load_multi_rows_query(keys)
        # Find fields with a common value for the below common_query optimization
        common_conditions = {}
        other_field_indexes = []
        key_fields.each_with_index do |field, i|
          first_value = keys.first[i]
          is_unique = keys.all? { |key_values| first_value == key_values[i] }

          if is_unique
            common_conditions[field] = first_value
          else
            other_field_indexes << i
          end
        end

        common_query = if common_conditions.any?
          # Optimization for the case of fields in which the key being searched
          # for is always the same. This results in simple equality conditions
          # being produced for these fields (e.g. "WHERE field = value").
          unsorted_model.where(common_conditions)
        end

        case other_field_indexes.size
        when 0
          common_query
        when 1
          # Micro-optimization for the case of a single unique field.
          # This results in a single "WHERE field IN (values)" statement being
          # produced from a single query.
          field_idx = other_field_indexes.first
          field_name = key_fields[i]
          field_values = keys.map { |key| key[field_idx] }
          (common_query || unsorted_model).where(field_name => field_values)
        else
          # More than one unique field, so we need to generate a query for each
          # set of values for each unique field.
          #
          # This results in multiple
          #   "WHERE field = value AND field_2 = value_2 OR ..."
          # statements being produced from an object like
          #   [{ field: value, field_2: value_2 }, ...]
          query = keys.reduce(nil) do |query, key|
            condition = {}
            other_field_indexes.each do |field_idx|
              field = key_fields[field_idx]
              condition[field] = key[field_idx]
            end
            subquery = unsorted_model.where(condition)

            query ? query.or(subquery) : subquery
          end

          if common_query
            common_query.merge(query)
          else
            query
          end
        end
      end

      def unsorted_model
        model.reorder(nil)
      end
    end
  end
end
