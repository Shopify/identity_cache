require 'active_record'
require 'active_support/core_ext/module/attribute_accessors'
require 'ar_transaction_changes'

require "identity_cache/version"
require 'identity_cache/memoized_cache_proxy'
require 'identity_cache/belongs_to_caching'
require 'identity_cache/cache_key_generation'
require 'identity_cache/configuration_dsl'
require 'identity_cache/parent_model_expiration'
require 'identity_cache/query_api'
require "identity_cache/cache_hash"
require "identity_cache/cache_invalidation"
require "identity_cache/cache_fetcher"
require "identity_cache/fallback_fetcher"

module IdentityCache
  CACHED_NIL = :idc_cached_nil
  BATCH_SIZE = 1000
  DELETED = :idc_cached_deleted
  DELETED_TTL = 1000

  class AlreadyIncludedError < StandardError; end
  class AssociationError < StandardError; end
  class InverseAssociationError < StandardError
    def initialize
      super "Inverse name for association could not be determined. Please use the :inverse_name option to specify the inverse association name for this cache."
    end
  end
  class UnsupportedScopeError < StandardError; end
  class UnsupportedAssociationError < StandardError; end
  class DerivedModelError < StandardError; end

  class << self
    include IdentityCache::CacheHash

    attr_accessor :readonly
    attr_writer :logger

    mattr_accessor :cache_namespace
    self.cache_namespace = "IDC:#{CACHE_VERSION}:".freeze

    def included(base) #:nodoc:
      raise AlreadyIncludedError if base.include?(IdentityCache::ConfigurationDSL)

      base.send(:include, ArTransactionChanges) unless base.include?(ArTransactionChanges)
      base.send(:include, IdentityCache::BelongsToCaching)
      base.send(:include, IdentityCache::CacheKeyGeneration)
      base.send(:include, IdentityCache::ConfigurationDSL)
      base.send(:include, IdentityCache::QueryAPI)
      base.send(:include, IdentityCache::CacheInvalidation)
    end

    # Sets the cache adaptor IdentityCache will be using
    #
    # == Parameters
    #
    # +cache_adaptor+ - A ActiveSupport::Cache::Store
    #
    def cache_backend=(cache_adaptor)
      if defined?(@cache)
        cache.cache_backend = cache_adaptor
      else
        @cache = MemoizedCacheProxy.new(cache_adaptor)
      end
    end

    def cache
      @cache ||= MemoizedCacheProxy.new
    end

    def logger
      @logger || Rails.logger
    end

    def should_fill_cache? # :nodoc:
      !readonly
    end

    def should_use_cache? # :nodoc:
      pool = ActiveRecord::Base.connection_pool
      !pool.active_connection? || pool.connection.open_transactions == 0
    end

    # Cache retrieval and miss resolver primitive; given a key it will try to
    # retrieve the associated value from the cache otherwise it will return the
    # value of the execution of the block.
    #
    # == Parameters
    # +key+ A cache key string
    #
    def fetch(key)
      if should_use_cache?
        unmap_cached_nil_for(cache.fetch(key) { map_cached_nil_for yield })
      else
        yield
      end
    end

    def map_cached_nil_for(value)
      value.nil? ? IdentityCache::CACHED_NIL : value
    end

    def unmap_cached_nil_for(value)
      value == IdentityCache::CACHED_NIL ? nil : value
    end

    # Same as +fetch+, except that it will try a collection of keys, using the
    # multiget operation of the cache adaptor.
    #
    # == Parameters
    # +keys+ A collection or array of key strings
    def fetch_multi(*keys)
      keys.flatten!(1)
      return {} if keys.size == 0

      result = if should_use_cache?
        fetch_in_batches(keys.uniq) do |missed_keys|
          results = yield missed_keys
          results.map {|e| map_cached_nil_for e }
        end
      else
        results = yield keys
        Hash[keys.zip(results)]
      end

      result.each do |key, value|
        result[key] = unmap_cached_nil_for(value)
      end

      result
    end

    private

    def fetch_in_batches(keys)
      keys.each_slice(BATCH_SIZE).each_with_object Hash.new do |slice, result|
        result.merge! cache.fetch_multi(*slice) {|missed_keys| yield missed_keys }
      end
    end
  end
end
