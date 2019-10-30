module IdentityCache
  class ExpiryHook # :nodoc:
    def initialize(cached_association)
      @cached_association = cached_association
    end

    attr_reader :cached_association

    def only_on_foreign_key_change?
      cached_association.embedded_by_reference?
    end
  end
end
