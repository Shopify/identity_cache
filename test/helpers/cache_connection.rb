# frozen_string_literal: true

module CacheConnection
  extend self

  # This patches AR::MemcacheStore to notify AS::Notifications upon read_multis like the rest of rails does
  module MemcachedStoreInstrumentation
    def read_multi(*args, &block)
      instrument("read_multi", "MULTI", keys: args) do
        super(*args, &block)
      end
    end
  end

  def host
    ENV["MEMCACHED_HOST"] || "127.0.0.1"
  end

  def port
    ENV["MEMCACHED_PORT"] || "11211"
  end

  def backend
    @backend ||= build_backend
  end

  def build_backend(address: "#{host}:#{port}")
    case ENV["ADAPTER"]
    when nil, "dalli"
      require "active_support/cache/mem_cache_store"
      ActiveSupport::Cache::MemCacheStore.new(address, failover: false, expires_in: 6.hours.to_i)
    when "memcached"
      require "memcached_store"
      require "active_support/cache/memcached_store"
      ActiveSupport::Cache::MemcachedStore.prepend(MemcachedStoreInstrumentation)
      ActiveSupport::Cache::MemcachedStore.new(address, support_cas: true, auto_eject_hosts: false)
    else
      raise "Unknown adapter: #{ENV["ADAPTER"]}"
    end
  end

  def unconnected_cache_backend
    @unconnected_cache_backend ||= build_backend(address: "127.0.0.1:#{find_open_port}").tap do |backend|
      backend.extend(IdentityCache::MemCacheStoreCAS) if backend.is_a?(ActiveSupport::Cache::MemCacheStore)
    end
  end

  def find_open_port
    socket = Socket.new(:INET, :STREAM)
    socket.bind(Addrinfo.tcp("127.0.0.1", 0))
    socket.local_address.ip_port
  ensure
    socket&.close
  end

  def setup
    IdentityCache.cache_backend = backend
  end
end
