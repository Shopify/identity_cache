# frozen_string_literal: true

module IdentityCache
  module ShouldUseCache
    extend ActiveSupport::Concern

    module ClassMethods
      def should_use_cache?
        IdentityCache.should_use_cache?
      end
    end

    private

    def mark_as_loaded_by_idc
      @loaded_by_idc = true
    end

    def loaded_by_idc?
      defined?(@loaded_by_idc)
    end
  end
end
