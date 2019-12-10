# frozen_string_literal: true

module IdentityCache
  module Cached
    class Attribute
      attr_reader :model, :alias_name, :key_fields, :unique

      def initialize(model, attribute_or_proc, alias_name, key_fields, unique)
        @model = model
        if attribute_or_proc.is_a?(Proc)
          @attribute_proc = attribute_or_proc
        else
          @attribute = attribute_or_proc.to_sym
        end
        @alias_name = alias_name.to_sym
        @key_fields = key_fields.map(&:to_sym)
        @unique = !!unique
      end

      def attribute
        @attribute ||= @attribute_proc.call.to_sym
      end

      def build
        cached_attribute = self

        model.define_singleton_method(:"fetch_#{fetch_method_suffix}") do |*key_values|
          raise_if_scoped
          cached_attribute.fetch(key_values)
        end

        if key_fields.length == 1
          model.define_singleton_method(:"fetch_multi_#{fetch_method_suffix}") do |index_values|
            raise_if_scoped
            cached_attribute.fetch_multi(index_values)
          end
        end
      end

      def fetch(key_values)
        key_fields.each_with_index do |field, i|
          key_values[i] = model.type_for_attribute(field.to_s).cast(key_values[i])
        end

        if model.should_use_cache?
          IdentityCache.fetch(input_key_to_cache_key(key_values)) do
            load_one_from_db(key_values)
          end
        else
          load_one_from_db(key_values)
        end
      end

      def fetch_multi(index_values)
        field = key_fields.first

        type = model.type_for_attribute(field)
        index_values = index_values.map { |value| type.cast(value) }

        unless model.should_use_cache?
          return load_multi_from_db(index_values)
        end

        index_by_cache_key = index_values.each_with_object({}) do |index_value, index_hash|
          cache_key = input_key_to_cache_key([index_value])
          index_hash[cache_key] = index_value
        end
        attribute_by_cache_key = IdentityCache.fetch_multi(index_by_cache_key.keys) do |unresolved_keys|
          unresolved_index_values = unresolved_keys.map { |cache_key| index_by_cache_key.fetch(cache_key) }
          resolved_attributes = load_multi_from_db(unresolved_index_values)
          unresolved_index_values.map { |index_value| resolved_attributes.fetch(index_value) }
        end
        result = {}
        attribute_by_cache_key.each do |cache_key, attribute_value|
          result[index_by_cache_key.fetch(cache_key)] = attribute_value
        end
        result
      end

      def expire(record)
        unless record.send(:was_new_record?)
          old_key = old_cache_key(record)
          IdentityCache.cache.delete(old_key)
        end
        unless record.destroyed?
          new_key = new_cache_key(record)
          if new_key != old_key
            IdentityCache.cache.delete(new_key)
          end
        end
      end

      def input_key_to_cache_key(key_values)
        values_hash = IdentityCache.memcache_hash(unhashed_values_cache_key_string(key_values))
        "#{model.rails_cache_key_namespace}#{cache_key_prefix}#{values_hash}"
      end

      private

      def load_one_from_db(key_values)
        query = model.reorder(nil).where(Hash[key_fields.zip(key_values)])
        query = query.limit(1) if unique
        results = query.pluck(attribute)
        unique ? results.first : results
      end

      def load_multi_from_db(index_values)
        key_field = key_fields.first
        rows = model.reorder(nil).where(key_field => index_values).pluck(key_field, attribute)
        result = {}
        default = unique ? nil : []
        index_values.each do |index_value|
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

      def unhashed_values_cache_key_string(values)
        values.map { |v| v.try!(:to_s).inspect }.join('/')
      end

      def cache_key_prefix
        @cache_key_prefix ||= begin
          unique_indicator = unique ? '' : 's'
          "attr#{unique_indicator}" \
            ":#{model.base_class.name}" \
            ":#{attribute}" \
            ":#{key_fields.join('/')}:"
        end
      end

      def new_cache_key(record)
        new_key_values = key_fields.map { |field| record.send(field) }
        input_key_to_cache_key(new_key_values)
      end

      def old_cache_key(record)
        old_key_values = key_fields.map do |field|
          field_string = field.to_s
          changes = record.transaction_changed_attributes
          if record.destroyed? && changes.key?(field_string)
            changes[field_string]
          elsif record.persisted? && changes.key?(field_string)
            changes[field_string]
          else
            record.send(field)
          end
        end
        input_key_to_cache_key(old_key_values)
      end

      def fetch_method_suffix
        "#{alias_name}_by_#{key_fields.join('_and_')}"
      end
    end
  end
end
