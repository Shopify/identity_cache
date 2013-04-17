module Rails

  class Cache < ActiveSupport::Cache::MemCacheStore
  end

  def self.cache
    @@cache ||= Cache.new("localhost:#{$memcached_port}")
  end

  class Logger
    def info(string)
    end

    def debug(string)
    end

    def error(string)
    end
  end

  def self.logger
    @logger = Logger.new
  end

  class Configuration
    def self.identity_cache_store
      ActiveSupport::Cache::MemCacheStore.new("localhost:#{$memcached_port}")
    end
  end

  def self.configuration
    @@configuration ||= Configuration.new
  end

end
