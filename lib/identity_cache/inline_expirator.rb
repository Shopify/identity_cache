module IdentityCache
  class InlineExpirator
    def expire(key)
      IdentityCache.logger.debug "Expiring key=#{key}"
      IdentityCache.cache.delete(key)
    end
  end
end