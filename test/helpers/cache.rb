require 'logger'

module Rails

  class Cache < ActiveSupport::Cache::MemCacheStore
  end

  def self.cache
    @@cache ||= Cache.new("localhost:#{$memcached_port}")
  end

  def self.logger
    @logger ||= Logger.new(nil)
  end
end
