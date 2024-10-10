# frozen_string_literal: true

module IdentityCache
  module Cached
    # @abstract
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

      def fetch(db_key)
        db_key = cast_db_key(db_key)

        if model.should_use_cache?
          IdentityCache.fetch(cache_key(db_key)) do
            load_one_from_db(db_key)
          end
        else
          load_one_from_db(db_key)
        end
      end

      def expire(record)
        all_deleted = true

        unless record.send(:was_new_record?)
          old_key = old_cache_key(record)

          if Thread.current[:idc_deferred_expiration]
            Thread.current[:idc_attributes_to_expire] << old_key
            # defer the deletion, and don't block the following deletion
            all_deleted = true
          else
            all_deleted = IdentityCache.cache.delete(old_key)
          end
        end
        unless record.destroyed?
          new_key = new_cache_key(record)
          if new_key != old_key
            if Thread.current[:idc_deferred_expiration]
              Thread.current[:idc_attributes_to_expire] << new_key
              all_deleted = true
            else
              all_deleted = IdentityCache.cache.delete(new_key) && all_deleted
            end
          end
        end

        all_deleted
      end

      def cache_key(index_key)
        values_hash = IdentityCache.memcache_hash(unhashed_values_cache_key_string(index_key))
        "#{model.rails_cache_key_namespace}#{cache_key_prefix}#{values_hash}"
      end

      def load_one_from_db(key)
        query = model.reorder(nil).where(load_from_db_where_conditions(key))
        query = query.limit(1) if unique
        results = query.pluck(attribute)
        unique ? results.first : results
      end

      def fetch_multi(keys)
        keys = keys.map { |key| cast_db_key(key) }

        unless model.should_use_cache?
          return load_multi_from_db(keys)
        end

        unordered_hash = CacheKeyLoader.load_multi(self, keys)

        # Calling `values` on the result is expected to return the values in the same order as their
        # corresponding keys. The fetch_multi_by_#{field_list} generated methods depend on this.
        keys.each_with_object({}) do |key, ordered_hash|
          ordered_hash[key] = unordered_hash.fetch(key)
        end
      end

      def load_multi_from_db(keys)
        result = {}
        return result if keys.empty?

        rows = load_multi_rows(keys)
        default = unique ? nil : []
        keys.each do |index_value|
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

      def cache_encode(db_value)
        db_value
      end
      alias_method :cache_decode, :cache_encode

      private

      # @abstract
      def cast_db_key(_index_key)
        raise NotImplementedError
      end

      # @abstract
      def unhashed_values_cache_key_string(_index_key)
        raise NotImplementedError
      end

      # @abstract
      def load_from_db_where_conditions(_index_key_or_keys)
        raise NotImplementedError
      end

      # @abstract
      def load_multi_rows(_index_keys)
        raise NotImplementedError
      end

      # @abstract
      def cache_key_from_key_values(_key_values)
        raise NotImplementedError
      end

      def field_types
        @field_types ||= key_fields.map { |field| model.type_for_attribute(field.to_s) }
      end

      def cache_key_prefix
        @cache_key_prefix ||= begin
          unique_indicator = unique ? "" : "s"
          "attr#{unique_indicator}" \
            ":#{model.base_class.name}" \
            ":#{attribute}" \
            ":#{key_fields.join("/")}:"
        end
      end

      def new_cache_key(record)
        new_key_values = key_fields.map { |field| record.send(field) }
        cache_key_from_key_values(new_key_values)
      end

      def old_cache_key(record)
        changes = record.transaction_changed_attributes
        old_key_values = key_fields.map do |field|
          field_string = field.to_s
          if record.destroyed? && changes.key?(field_string)
            changes[field_string]
          elsif record.persisted? && changes.key?(field_string)
            changes[field_string]
          else
            record.send(field)
          end
        end
        cache_key_from_key_values(old_key_values)
      end

      def fetch_method_suffix
        "#{alias_name}_by_#{key_fields.join("_and_")}"
      end
    end
  end
end
