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

        model.define_singleton_method(:"fetch_multi_#{fetch_method_suffix}") do |key_values|
          raise_if_scoped
          cached_attribute.fetch_multi(*key_values)
        end
      end

      def fetch_multi(*key_values)
        key_values = key_values.map do |key_value|
          cast_db_key(key_value)
        end

        unless model.should_use_cache?
          return load_multi_from_db(key_values)
        end

        unordered_hash = CacheKeyLoader.load_multi(self, key_values)

        # Calling `values` on the result is expected to return the values in the same order as their
        # corresponding keys. The fetch_multi_by_#{field_list} generated methods depend on this.
        ordered_hash = {}
        key_values.each { |key_value| ordered_hash[key_value] = unordered_hash.fetch(key_value) }
        ordered_hash
      end

      def load_multi_from_db(key_values)
        rows = unsorted_model_with_where_conditions(key_values).pluck(attribute, *key_fields)
        result = {}
        default = unique ? nil : []
        key_values.each do |index_value|
          result[index_value] = default.try!(:dup)
        end
        if unique
          rows.each do |attribute_value, *index_values|
            result[index_values] = attribute_value
          end
        else
          rows.each do |attribute_value, *index_values|
            result[index_values] << attribute_value
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

      def unsorted_model_with_where_conditions(key_values)
        unsorted_model = model.reorder(nil)
        conditions = key_values.map do |keys|
          key_fields.each_with_object({}).with_index do |(field, conds), i|
            conds[field] = keys[i]
          end
        end

        conditions.reduce(nil) do |query, condition|
          if query.nil?
            unsorted_model.where(condition)
          else
            query.or(unsorted_model.where(condition))
          end
        end
      end

      def cast_db_key(key_values)
        field_types.each_with_index do |type, i|
          key_values[i] = type.cast(key_values[i])
        end
        key_values
      end

      def unhashed_values_cache_key_string(key_values)
        key_values.map { |v| v.try!(:to_s).inspect }.join("/")
      end

      def load_from_db_where_conditions(key_values)
        Hash[key_fields.zip(key_values)]
      end

      alias_method :cache_key_from_key_values, :cache_key
    end
  end
end
