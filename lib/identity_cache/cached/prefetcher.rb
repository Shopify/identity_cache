# frozen_string_literal: true

module IdentityCache
  module Cached
    module Prefetcher
      ASSOCIATION_FETCH_EVENT = "association_fetch.identity_cache"

      class << self
        def prefetch(klass, associations, records, load_strategy: LoadStrategy::Eager)
          load_strategy.lazy_load do |lazy_loader|
            lazy_prefetch(lazy_loader, klass, associations, records)
          end
        end

        def lazy_prefetch(lazy_loader, klass, associations, records)
          return if (records = records.to_a).empty?

          case associations
          when Symbol
            fetch_association(lazy_loader, klass, associations, records) { }
          when Array
            associations.each do |association|
              lazy_prefetch(lazy_loader, klass, association, records)
            end
          when Hash
            associations.each do |association, sub_associations|
              fetch_association(lazy_loader, klass, association, records) do |next_level_records|
                if sub_associations.present?
                  association_class = klass.reflect_on_association(association).klass
                  lazy_prefetch(lazy_loader, association_class, sub_associations, next_level_records)
                end
              end
            end
          else
            raise TypeError, "Invalid associations class #{associations.class}"
          end
        end

        private

        def fetch_association(lazy_loader, klass, association, records, &block)
          unless records.first.class.should_use_cache?
            ActiveRecord::Associations::Preloader.new.preload(records, association)
            return yield
          end

          cached_association = klass.cached_association(association)
          cached_association.fetch_async(lazy_loader, records, &block)
        end
      end
    end
  end
end
