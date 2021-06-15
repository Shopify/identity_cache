# frozen_string_literal: true
module IdentityCache
  module WithoutPrimaryIndex
    extend ActiveSupport::Concern

    include ArTransactionChanges
    include IdentityCache::BelongsToCaching
    include IdentityCache::CacheKeyGeneration
    include IdentityCache::ConfigurationDSL
    include IdentityCache::QueryAPI
    include IdentityCache::CacheInvalidation
    include IdentityCache::ShouldUseCache
    include ParentModelExpiration

    def self.append_features(base) #:nodoc:
      raise AlreadyIncludedError if base.include?(WithoutPrimaryIndex)
      super
    end

    included do
      class_attribute(:cached_model)
      self.cached_model = self
    end

    module ClassMethods
      def primary_cache_index_enabled
        false
      end

      # Get only the columns whose values are needed to manually expire caches
      # after updating or deleting rows without triggering after_commit callbacks.
      #
      # 1. Pass the returned columns into Active Record's `select` or `pluck` query
      #    method on the scope that will be used to modify the database in order to
      #    query original for these rows that will be modified.
      # 2. Update or delete the rows
      # 3. Use {expire_cache_for_update} or {expire_cache_for_delete} to expires the
      #    caches, passing in the values from the query in step 1 as the indexed_values.
      #
      # @return [Array<Symbol>] the array of column names
      def cache_indexed_columns
        @cache_indexed_columns ||= begin
          check_for_unsupported_parent_expiration_entries
          columns = Set.new
          columns << primary_key.to_sym if primary_cache_index_enabled
          cache_indexes.each do |cached_attribute|
            columns.merge(cached_attribute.key_fields)
          end
          columns.to_a.freeze
        end
      end

      def expire_cache_for_update(old_indexed_values, changes)
        if primary_cache_index_enabled
          id = old_indexed_values.fetch(primary_key.to_sym)
          expire_primary_key_cache_index(id)
        end
        cache_indexes.each do |cached_attribute|
          cached_attribute.expire_for_update(old_indexed_values, changes)
        end
        check_for_unsupported_parent_expiration_entries
      end

      private def expire_cache_for_insert_or_delete(indexed_values)
        if primary_cache_index_enabled
          id = indexed_values.fetch(primary_key.to_sym)
          expire_primary_key_cache_index(id)
        end
        cache_indexes.each do |cached_attribute|
          cached_attribute.expire_for_values(indexed_values)
        end
        check_for_unsupported_parent_expiration_entries
      end

      alias_method :expire_cache_for_insert, :expire_cache_for_insert_or_delete

      alias_method :expire_cache_for_delete, :expire_cache_for_insert_or_delete

      private

      def check_for_unsupported_parent_expiration_entries
        return unless parent_expiration_entries.any?
        msg = +"Unsupported manual expiration of #{name} record that is embedded in parent associations:\n"
        parent_expiration_entries.each do |association_name, cached_associations|
          cached_associations.each do |parent_class, _only_on_foreign_key_change|
            msg << "- #{association_name}"
          end
        end
        raise msg
      end
    end
  end
end
