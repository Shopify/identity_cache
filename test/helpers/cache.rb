module Rails

  class Cache < ActiveSupport::Cache::MemCacheStore
  end

  def self.cache
    @@cache ||= Cache.new
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
end
