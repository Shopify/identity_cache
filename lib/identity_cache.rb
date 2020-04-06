# frozen_string_literal: true
require 'active_record'
require 'active_support/core_ext/module/attribute_accessors'
require 'ar_transaction_changes'

require "identity_cache/version"
require "identity_cache/record_not_found"
require "identity_cache/encoder"
require "identity_cache/cache_key_loader"
require "identity_cache/load_strategy/load_request"
require "identity_cache/load_strategy/multi_load_request"
require "identity_cache/load_strategy/eager"
require "identity_cache/load_strategy/lazy"
require "identity_cache/cached"
require "identity_cache/cached/prefetcher"
require "identity_cache/cached/embedded_fetching"
require "identity_cache/cached/association"
require "identity_cache/cached/attribute"
require "identity_cache/cached/attribute_by_one"
require "identity_cache/cached/attribute_by_multi"
require "identity_cache/cached/belongs_to"
require "identity_cache/cached/primary_index"
require "identity_cache/cached/recursive/association"
require "identity_cache/cached/recursive/has_one"
require "identity_cache/cached/recursive/has_many"
require "identity_cache/cached/reference/association"
require "identity_cache/cached/reference/has_one"
require "identity_cache/cached/reference/has_many"
require "identity_cache/expiry_hook"
require 'identity_cache/memoized_cache_proxy'
require 'identity_cache/belongs_to_caching'
require 'identity_cache/cache_key_generation'
require 'identity_cache/configuration_dsl'
require 'identity_cache/should_use_cache'
require 'identity_cache/parent_model_expiration'
require 'identity_cache/query_api'
require "identity_cache/cache_hash"
require "identity_cache/cache_invalidation"
require "identity_cache/cache_fetcher"
require "identity_cache/fallback_fetcher"
require 'identity_cache/without_primary_index'
require 'identity_cache/with_primary_index'
require "identity_cache/tracking"

module IdentityCache
  extend ActiveSupport::Concern

  include WithPrimaryIndex

  CACHED_NIL = :idc_cached_nil
  BATCH_SIZE = 1000
  DELETED = :idc_cached_deleted
  DELETED_TTL = 1000

  class AlreadyIncludedError < StandardError; end
  class AssociationError < StandardError; end
  class InverseAssociationError < StandardError; end
  class UnsupportedScopeError < StandardError; end
  class UnsupportedAssociationError < StandardError; end
  class DerivedModelError < StandardError; end

  mattr_accessor :cache_namespace
  self.cache_namespace = "IDC:#{CACHE_VERSION}:"

  # Fetched records are not read-only and this could sometimes prevent IDC from
  # reflecting what's truly in the database when fetch_read_only_records is false.
  # When set to true, it will only return read-only records when cache is used.
  mattr_accessor :fetch_read_only_records
  self.fetch_read_only_records = true

  class << self
    include IdentityCache::CacheHash

    attr_accessor :readonly
    attr_writer :logger

    def append_features(base) #:nodoc:
      raise AlreadyIncludedError if base.include?(IdentityCache)
      super
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
      return {} if keys.empty?

      result = if should_use_cache?
        fetch_in_batches(keys.uniq) do |missed_keys|
          results = yield missed_keys
          results.map { |e| map_cached_nil_for e }
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

    def with_fetch_read_only_records(value = true)
      old_value = fetch_read_only_records
      self.fetch_read_only_records = value
      yield
    ensure
      self.fetch_read_only_records = old_value
    end

    def eager_load!
      ParentModelExpiration.install_all_pending_parent_expiry_hooks
    end

    private

    def fetch_in_batches(keys)
      keys.each_slice(BATCH_SIZE).each_with_object({}) do |slice, result|
        result.merge!(cache.fetch_multi(*slice) { |missed_keys| yield missed_keys })
      end
    end
  end
end

require 'identity_cache/railtie' if defined?(Rails)
