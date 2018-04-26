module CacheConnection
  extend self

  def host
    ENV['MEMCACHED_HOST'] || "127.0.0.1"
  end

  def backend
    @backend ||= ActiveSupport::Cache::DalliStore.new("#{host}:11211")
  end

  def setup
    IdentityCache.cache_backend = backend
  end
end
