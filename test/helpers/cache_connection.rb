module CacheConnection
  extend self

  def host
    ENV['MEMCACHED_HOST'] || "127.0.0.1"
  end

  def backend
    @backend ||= ActiveSupport::Cache::MemcachedStore.new("#{host}:11211", support_cas: true)
  end

  def setup
    IdentityCache.cache_backend = backend
  end
end
