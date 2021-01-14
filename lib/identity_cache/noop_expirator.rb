module IdentityCache
  class NoopExpirator
    def expire(*)
      #NOOP
    end
  end
end