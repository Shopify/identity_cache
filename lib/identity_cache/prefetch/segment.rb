module IdentityCache
  module Prefetch
    class Segment
      ASSOCIATION_FETCH_EVENT = "association_fetch.identity_cache"

      def initialize(batch, cached_association, provider)
        @batch = batch
        @cached_association = cached_association
        @provider = provider
      end

      def load
        ActiveSupport::Notifications.instrument(ASSOCIATION_FETCH_EVENT, association: association) do
          records
        end
      end

      def records
        @records ||= if @cached_association.reflection.active_record.should_use_cache?
          @cached_association.fetch(@provider.records)
        else
          ActiveRecord::Associations::Preloader.new.preload(@provider.records, association)
          @provider.records
        end
      end

      private

      def association
        @cached_association.name
      end
    end
  end
end
