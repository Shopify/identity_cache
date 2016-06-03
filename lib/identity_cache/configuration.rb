module IdentityCache
  module Configuration
    extend ActiveSupport::Concern

    module ClassMethods

      def should_fill_cache? # :nodoc:
        IdentityCache.should_fill_cache?
      end

      def should_use_cache? # :nodoc:
        IdentityCache.should_use_cache?
      end

    end

  end
end
