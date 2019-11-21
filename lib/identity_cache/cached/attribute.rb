# frozen_string_literal: true

module IdentityCache
  module Cached
    class Attribute < AbstractFetcher
      attr_reader :model, :attribute, :alias_name, :key_fields, :unique

      def initialize(model, attribute, alias_name, key_fields, unique)
        @model = model
        @attribute = attribute
        @alias_name = alias_name
        @key_fields = key_fields
        @unique = unique
      end

      private

      # AbstractFetcher method overrides

      def should_use_cache?
        model.should_use_cache?
      end

      def input_key_to_cache_key(index_key)
        model.rails_cache_key_for_attribute_and_fields_and_values(attribute, key_fields, index_key, unique)
      end

      def default_value
        unique ? nil : []
      end

      def load_from_db(index_key)
        query = model.reorder(nil).where(load_from_db_where_conditions(index_key))
        query = query.limit(1) if unique
        results = query.pluck(attribute)
        unique ? results.first : results
      end

      # helper methods

      def load_from_db_where_conditions(index_key)
        raise NotImplementedError
      end

      def fetch_method_suffix
        field_list = key_fields.join("_and_")
        arg_list = (0...key_fields.size).collect { |i| "arg#{i}" }.join(',')
        "#{alias_name}_by_#{field_list}"
      end
    end
  end
end
