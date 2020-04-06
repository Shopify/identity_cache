# frozen_string_literal: true
module IdentityCache
  module CacheKeyGeneration
    extend ActiveSupport::Concern
    DEFAULT_NAMESPACE = "IDC:#{CACHE_VERSION}:"

    def self.schema_to_string(columns)
      columns.sort_by(&:name).map { |c| "#{c.name}:#{c.type}" }.join(',')
    end

    def self.denormalized_schema_string(klass)
      schema_to_string(klass.columns).tap do |schema_string|
        klass.all_cached_associations.sort.each do |name, association|
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
      def rails_cache_key_namespace
        ns = IdentityCache.cache_namespace
        ns.is_a?(Proc) ? ns.call(self) : ns
      end
    end
  end
end
