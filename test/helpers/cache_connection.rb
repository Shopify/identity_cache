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
    ENV['MEMCACHED_HOST'] || "127.0.0.1"
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
    else
      raise "Unknown adapter: #{ENV['ADAPTER']}"
    end
  end

  def setup
    IdentityCache.cache_backend = backend
  end
end
