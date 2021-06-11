# frozen_string_literal: true

module IdentityCache
  module Internal
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
        cache_key_from_key_values(old_key_values)
      end

      def fetch_method_suffix
        "#{alias_name}_by_#{key_fields.join("_and_")}"
      end
    end
  end
end
