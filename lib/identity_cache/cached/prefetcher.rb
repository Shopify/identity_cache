# frozen_string_literal: true

module IdentityCache
  module Cached
    module Prefetcher
      ASSOCIATION_FETCH_EVENT = "association_fetch.identity_cache"

      class << self
        def prefetch(klass, associations, records)
          return if (records = records.to_a).empty?

          case associations
          when Symbol
            prefetch_association(klass, associations, records)
          when Array
            associations.each do |association|
              prefetch(klass, association, records)
            end
          when Hash
            associations.each do |association, sub_associations|
              next_level_records = prefetch_association(klass, association, records)

              if sub_associations.present?
                association_class = klass.reflect_on_association(association).klass
                prefetch(association_class, sub_associations, next_level_records)
              end
            end
          else
            raise TypeError, "Invalid associations class #{associations.class}"
          end
        end

        private

        def prefetch_association(klass, association, records)
          ActiveSupport::Notifications.instrument(ASSOCIATION_FETCH_EVENT, association: association) do
            fetch_association(klass, association, records)
          end
        end

        def fetch_association(klass, association, records)
          unless records.first.class.should_use_cache?
            ActiveRecord::Associations::Preloader.new.preload(records, association)
            return
          end

          cached_association = klass.cached_association(association)
          cached_association.fetch(records)
        end
      end
    end
  end
end
