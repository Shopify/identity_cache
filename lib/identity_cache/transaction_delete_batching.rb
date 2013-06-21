module IdentityCache
  module TransactionDeleteBatching

    def self.included(base)
      base.extend(ClassMethods)
      meta = class << base ; self ; end
      meta.send(:alias_method_chain, :transaction, :idc_batching)
    end

    module ClassMethods
      def transaction_with_idc_batching(options={}, &block)
        IdentityCache.cache.begin_batch
        transaction_without_idc_batching(options={}, &block)
      ensure
        IdentityCache.cache.end_batch
      end
    end

  end
end

ActiveRecord::Base.send(:include, IdentityCache::TransactionDeleteBatching)
