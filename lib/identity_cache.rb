require 'cityhash'
require 'ar_transaction_changes'
require "identity_cache/version"
require 'identity_cache/memoized_cache_proxy'
require 'identity_cache/belongs_to_caching'
require 'identity_cache/cache_key_generation'
require 'identity_cache/configuration_dsl'
require 'identity_cache/parent_model_expiration'
require 'identity_cache/query_api'

module IdentityCache
  CACHED_NIL = :idc_cached_nil

  class AlreadyIncludedError < StandardError; end
  class InverseAssociationError < StandardError
    def initialize
      super "Inverse name for association could not be determined. Please use the :inverse_name option to specify the inverse association name for this cache."
    end
  end

  class << self

    attr_accessor :logger, :readonly
    attr_reader :cache

    # Sets the cache adaptor IdentityCache will be using
    #
    # == Parameters
    #
    # +cache_adaptor+ - A ActiveSupport::Cache::Store
    #
    def cache_backend=(cache_adaptor)
      cache.memcache = cache_adaptor
    end

    def cache
      @cache ||= MemoizedCacheProxy.new
    end

    def logger
      @logger || Rails.logger
    end

    def should_cache? # :nodoc:
      !readonly && ActiveRecord::Base.connection.open_transactions == 0
    end

    # Cache retrieval and miss resolver primitive; given a key it will try to
    # retrieve the associated value from the cache otherwise it will return the
    # value of the execution of the block.
    #
    # == Parameters
    # +key+ A cache key string
    #
    def fetch(key, &block)
      result = cache.read(key) if should_cache?

      if result.nil?
        if block_given?
          ActiveRecord::Base.connection.with_master do
            result = yield
          end
          result = map_cached_nil_for(result)

          if should_cache?
            cache.write(key, result)
          end
        end
        logger.debug "[IdentityCache] cache miss for #{key}"
      else
        logger.debug "[IdentityCache] cache hit for #{key}"
      end

      unmap_cached_nil_for(result)
    end

    def map_cached_nil_for(value)
      value.nil? ? IdentityCache::CACHED_NIL : value
    end


    def unmap_cached_nil_for(value)
      value == IdentityCache::CACHED_NIL ? nil : value
    end

    # Same as +fetch+, except that it will try a collection of keys, using the
    # multiget operation of the cache adaptor
    #
    # == Parameters
    # +keys+ A collection of key strings
    def fetch_multi(*keys, &block)
      return {} if keys.size == 0
      result = {}
      result = cache.read_multi(*keys) if should_cache?

      hit_keys = result.select {|key, value| value.present? }.keys
      missed_keys = keys - hit_keys

      if missed_keys.size > 0
        if block_given?
          replacement_results = nil
          ActiveRecord::Base.connection.with_master do
            replacement_results = yield missed_keys
          end
          missed_keys.zip(replacement_results) do |(key, replacement_result)|
            if should_cache?
              replacement_result  = map_cached_nil_for(replacement_result )
              cache.write(key, replacement_result)
              logger.debug "[IdentityCache] cache miss for #{key} (multi)"
            end
            result[key] = replacement_result
          end
        end
      end

      hit_keys.each do |key|
        logger.debug "[IdentityCache] cache hit for #{key} (multi)"
      end

      result.keys.each do |key|
        result[key] = unmap_cached_nil_for(result[key])
      end

      result
    end

    def schema_to_string(columns)
      columns.sort_by(&:name).map {|c| "#{c.name}:#{c.type}"} * ","
    end

    def included(base) #:nodoc:
      raise AlreadyIncludedError if base.respond_to? :cache_indexes

      unless ActiveRecord::Base.connection.respond_to?(:with_master)
        ActiveRecord::Base.connection.class.class_eval(ruby = <<-CODE, __FILE__, __LINE__)
          def with_master
            yield
          end
        CODE
      end

      base.send(:include, ArTransactionChanges) unless base.include?(ArTransactionChanges)
      base.send(:include, IdentityCache::BelongsToCaching)
      base.send(:include, IdentityCache::CacheKeyGeneration)
      base.send(:include, IdentityCache::ConfigurationDSL)
      base.send(:include, IdentityCache::QueryAPI)
    end

    def memcache_hash(key) #:nodoc:
      CityHash.hash64(key)
    end
  end
end
