module IdentityCache
  module CacheKeyGeneration
    extend ActiveSupport::Concern
    DEFAULT_NAMESPACE = "IDC:#{CACHE_VERSION}:".freeze

    def self.schema_to_string(columns)
      columns.sort_by(&:name).map{|c| "#{c.name}:#{c.type}"}.join(',')
    end

    def self.denormalized_schema_hash(klass)
      schema_string = schema_to_string(klass.columns)
      if klass.include?(IdentityCache)
        klass.send(:all_cached_associations).sort.each do |name, options|
          case options[:embed]
          when true
            schema_string << ",#{name}:(#{denormalized_schema_hash(options[:association_class].klass)})"
          when :ids
            schema_string << ",#{name}:ids"
          end
        end
      end
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

      def rails_cache_index_key_for_fields_and_values(fields, values)
        "#{rails_cache_key_namespace}index:#{base_class.name}:#{rails_cache_string_for_fields_and_values(fields, values)}"
      end

      def rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values)
        "#{rails_cache_key_namespace}attribute:#{base_class.name}:#{attribute}:#{rails_cache_string_for_fields_and_values(fields, values)}"
      end

      def rails_cache_key_namespace
        ns = IdentityCache.cache_namespace
        ns.is_a?(Proc) ? ns.call(self) : ns
      end

      private
      def rails_cache_string_for_fields_and_values(fields, values)
        "#{fields.join('/')}:#{IdentityCache.memcache_hash(values.join('/'))}"
      end
    end

    def primary_cache_index_key # :nodoc:
      self.class.rails_cache_key(id)
    end

    def secondary_cache_index_key_for_current_values(fields) # :nodoc:
      self.class.rails_cache_index_key_for_fields_and_values(fields, current_values_for_fields(fields))
    end

    def secondary_cache_index_key_for_previous_values(fields) # :nodoc:
      self.class.rails_cache_index_key_for_fields_and_values(fields, old_values_for_fields(fields))
    end

    def attribute_cache_key_for_attribute_and_current_values(attribute, fields) # :nodoc:
      self.class.rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, current_values_for_fields(fields))
    end

    def attribute_cache_key_for_attribute_and_previous_values(attribute, fields) # :nodoc:
      self.class.rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, old_values_for_fields(fields))
    end

    def current_values_for_fields(fields) # :nodoc:
      fields.collect {|field| self.send(field)}
    end

    def old_values_for_fields(fields) # :nodoc:
      fields.map do |field|
        field_string = field.to_s
        if destroyed? && transaction_changed_attributes.has_key?(field_string)
          transaction_changed_attributes[field_string]
        elsif persisted? && transaction_changed_attributes.has_key?(field_string)
          transaction_changed_attributes[field_string]
        else
          self.send(field)
        end
      end
    end
  end
end
