module IdentityCache
  module CacheKeyGeneration
    extend ActiveSupport::Concern
    DEFAULT_NAMESPACE = "IDC:#{CACHE_VERSION}:".freeze

    class << self
      def schema_to_string(columns)
        columns.sort_by(&:name).map { |c| "#{c.name}:#{c.type}" }.join(',')
      end

      def denormalized_schema_hash(klass)
        schema_string = schema_to_string(klass.columns)
        klass.send(:all_cached_associations).sort.each do |name, options|
          klass.send(:check_association_scope, name)
          ParentModelExpiration.check_association(options) if options[:embed]
          case options[:embed]
          when true
            schema_string << ",#{name}:(#{denormalized_schema_hash(options[:association_reflection].klass)})"
          when :ids
            schema_string << ",#{name}:ids"
          end
        end
        IdentityCache.memcache_hash(schema_string)
      end

      def evaluate_namespace(model, namespace)
        case namespace
        when Proc
          namespace.call(model)
        else
          namespace
        end
      end

      def prefixed_rails_cache_key(model_class, namespace)
        "#{namespace}blob:#{model_class.base_class.name}:#{model_class.rails_cache_key_prefix}:"
      end

      def rails_cache_key_for_attribute_and_fields_and_values(model, namespace, attribute, fields, values, unique)
        unique_indicator = unique ? '' : 's'
        "#{namespace}" \
          "attr#{unique_indicator}" \
          ":#{model.base_class.name}" \
          ":#{attribute}" \
          ":#{rails_cache_string_for_fields_and_values(fields, values)}"
      end

      private

      def rails_cache_string_for_fields_and_values(fields, values)
        "#{fields.join('/')}:#{IdentityCache.memcache_hash(values.join('/'))}"
      end
    end

    module ClassMethods
      def rails_cache_key(id)
        "#{prefixed_rails_cache_key}#{id}"
      end

      def rails_cache_keys(id)
        prefixed_rails_cache_keys.map do |prefix|
          "#{prefix}#{id}"
        end
      end

      def rails_cache_key_prefix
        @rails_cache_key_prefix ||= IdentityCache::CacheKeyGeneration.denormalized_schema_hash(self)
      end

      def prefixed_rails_cache_key
        CacheKeyGeneration.prefixed_rails_cache_key(self, rails_cache_key_namespace)
      end

      def prefixed_rails_cache_keys
        rails_cache_key_namespaces.map do |namespace|
          CacheKeyGeneration.prefixed_rails_cache_key(self, namespace)
        end
      end

      def rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values, unique)
        CacheKeyGeneration.rails_cache_key_for_attribute_and_fields_and_values(
          self,
          rails_cache_key_namespace,
          attribute,
          fields,
          values,
          unique,
        )
      end

      def rails_cache_keys_for_attribute_and_fields_and_values(attribute, fields, values, unique)
        rails_cache_key_namespaces.map do |namespace|
          CacheKeyGeneration.rails_cache_key_for_attribute_and_fields_and_values(
            self,
            namespace,
            attribute,
            fields,
            values,
            unique,
          )
        end
      end

      def rails_cache_key_namespace
        CacheKeyGeneration.evaluate_namespace(self, IdentityCache.cache_namespace)
      end

      def rails_cache_key_namespaces
        alternate_cache_namespace = IdentityCache.alternate_cache_namespace
        if alternate_cache_namespace
          [
            rails_cache_key_namespace,
            CacheKeyGeneration.evaluate_namespace(self, alternate_cache_namespace),
          ]
        else
          [rails_cache_key_namespace]
        end
      end
    end

    def primary_cache_index_key # :nodoc:
      self.class.rails_cache_key(id)
    end

    def primary_cache_index_keys # :nodoc:
      self.class.rails_cache_keys(id)
    end

    def attribute_cache_key_for_attribute_and_current_values(attribute, fields, unique) # :nodoc:
      self.class.rails_cache_key_for_attribute_and_fields_and_values(
        attribute, fields, current_values_for_fields(fields), unique,
      )
    end

    def attribute_cache_keys_for_attribute_and_current_values(attribute, fields, unique) # :nodoc:
      self.class.rails_cache_keys_for_attribute_and_fields_and_values(
        attribute, fields, current_values_for_fields(fields), unique,
      )
    end

    def attribute_cache_key_for_attribute_and_previous_values(attribute, fields, unique) # :nodoc:
      self.class.rails_cache_key_for_attribute_and_fields_and_values(
        attribute, fields, old_values_for_fields(fields), unique,
      )
    end

    def attribute_cache_keys_for_attribute_and_previous_values(attribute, fields, unique) # :nodoc:
      self.class.rails_cache_keys_for_attribute_and_fields_and_values(
        attribute, fields, old_values_for_fields(fields), unique,
      )
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
