require 'logger'
require 'active_support/cache/memcached_store'

module Rails

  class Cache < ActiveSupport::Cache::MemcachedStore
  end

  def self.cache
    @@cache ||= Cache.new("localhost:#{$memcached_port}")
  end

  def self.logger
    @logger ||= Logger.new(nil)
  end
end
