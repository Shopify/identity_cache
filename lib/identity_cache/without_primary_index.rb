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

    # @api private
    attr_accessor :loaded_from_identity_cache

    def destroy
      warn_cached_record_mutation if loaded_from_identity_cache && !readonly?
      super
    end

    def save(**options, &block)
      warn_cached_record_mutation if loaded_from_identity_cache && !readonly?
      super
    end

    private

    def warn_cached_record_mutation
      ActiveSupport::Deprecation.warn("Mutation of cache fetched #{self.class} record")
    end

    module ClassMethods
      def primary_cache_index_enabled
        false
      end
    end
  end
end
