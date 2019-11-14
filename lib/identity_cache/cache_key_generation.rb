# frozen_string_literal: true
module IdentityCache
  module CacheKeyGeneration
    extend ActiveSupport::Concern
    DEFAULT_NAMESPACE = "IDC:#{CACHE_VERSION}:"

    def self.schema_to_string(columns)
      columns.sort_by(&:name).map{ |c| "#{c.name}:#{c.type}" }.join(',')
    end

    def self.denormalized_schema_string(klass)
      schema_to_string(klass.columns).tap do |schema_string|
        klass.send(:all_cached_associations).sort.each do |name, association|
          klass.send(:check_association_scope, name)
          association.validate if association.embedded?
          case association
          when Cached::Recursive::Association
            schema_string << ",#{name}:(#{denormalized_schema_hash(association.reflection.klass)})"
          when Cached::Reference::HasMany
            schema_string << ",#{name}:ids"
          when Cached::Reference::HasOne
            schema_string << ",#{name}:id"
          end
        end
      end
    end

    def self.denormalized_schema_hash(klass)
      schema_string = denormalized_schema_string(klass)
      IdentityCache.memcache_hash(schema_string)
    end

    module ClassMethods
      def rails_cache_key(id)
        "#{prefixed_rails_cache_key}#{id}"
      end

      def rails_cache_key_prefix
        @rails_cache_key_prefix ||= IdentityCache::CacheKeyGeneration.denormalized_schema_hash(self)
      end

      def prefixed_rails_cache_key
        "#{rails_cache_key_namespace}blob:#{base_class.name}:#{rails_cache_key_prefix}:"
      end

      def rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values, unique)
        unique_indicator = unique ? '' : 's'
        "#{rails_cache_key_namespace}" \
          "attr#{unique_indicator}" \
          ":#{base_class.name}" \
          ":#{attribute}" \
          ":#{rails_cache_string_for_fields_and_values(fields, values)}"
      end

      def rails_cache_key_namespace
        ns = IdentityCache.cache_namespace
        ns.is_a?(Proc) ? ns.call(self) : ns
      end

      private
      def rails_cache_string_for_fields_and_values(fields, values)
        "#{fields.join('/')}:#{IdentityCache.memcache_hash(values.map { |v| v.try!(:to_s).inspect }.join('/'))}"
      end
    end

    def primary_cache_index_key # :nodoc:
      self.class.rails_cache_key(id)
    end

    def attribute_cache_key_for_attribute_and_current_values(attribute, fields, unique) # :nodoc:
      self.class.rails_cache_key_for_attribute_and_fields_and_values(
        attribute, fields, current_values_for_fields(fields), unique
      )
    end

    def attribute_cache_key_for_attribute_and_previous_values(attribute, fields, unique) # :nodoc:
      self.class.rails_cache_key_for_attribute_and_fields_and_values(
        attribute, fields, old_values_for_fields(fields), unique
      )
    end

    def current_values_for_fields(fields) # :nodoc:
      fields.collect { |field| send(field) }
    end

    def old_values_for_fields(fields) # :nodoc:
      fields.map do |field|
        field_string = field.to_s
        if destroyed? && transaction_changed_attributes.has_key?(field_string)
          transaction_changed_attributes[field_string]
        elsif persisted? && transaction_changed_attributes.has_key?(field_string)
          transaction_changed_attributes[field_string]
        else
          send(field)
        end
      end
    end
  end
end
