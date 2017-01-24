module IdentityCache
  module WithoutPrimaryIndex
    extend ActiveSupport::Concern

    included do |base|
      base.send(:include, IdentityCache)
      base.primary_cache_index_enabled = false
    end
  end
end
