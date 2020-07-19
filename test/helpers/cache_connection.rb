# frozen_string_literal: true
module CacheConnection
  extend self

  # This patches AR::MemcacheStore to notify AS::Notifications upon read_multis like the rest of rails does
  module MemcachedStoreInstrumentation
    def read_multi(*args, &block)
      instrument('read_multi', 'MULTI', keys: args) do
        super(*args, &block)
      end
    end
  end

  def host
    default = "127.0.0.1"
    case ENV['ADAPTER']
    when 'redis'
      ENV['REDIS_URL'] || default
    else
      ENV['MEMCACHED_HOST'] || default
    end
  end

  def backend
    @backend ||= case ENV['ADAPTER']
    when nil, 'dalli'
      require 'active_support/cache/mem_cache_store'
      ActiveSupport::Cache::MemCacheStore.new("#{host}:11211", failover: false)
    when 'memcached'
      require 'memcached_store'
      require 'active_support/cache/memcached_store'
      ActiveSupport::Cache::MemcachedStore.prepend(MemcachedStoreInstrumentation)
      ActiveSupport::Cache::MemcachedStore.new("#{host}:11211", support_cas: true, auto_eject_hosts: false)
    when 'redis'
      require 'hiredis'
      require 'redis'
      require 'identity_cache/redis_cas'
      require 'active_support/cache/redis_cache_store'
      puts 'here'
      Redis.include(IdentityCache::RedisCAS)
      ActiveSupport::Cache::RedisCacheStore.include(MemcachedStoreInstrumentation)
      ActiveSupport::Cache::RedisCacheStore.new(expires_in: 90.minutes, url: host)
    else
      raise "Unknown adapter: #{ENV['ADAPTER']}"
    end
  end

  def setup
    IdentityCache.cache_backend = backend
  end
end
