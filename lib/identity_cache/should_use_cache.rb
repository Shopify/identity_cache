module IdentityCache
  module ShouldUseCache
    extend ActiveSupport::Concern

    module ClassMethods
      def should_use_cache?
        IdentityCache.should_use_cache?
      end
    end
  end
end
