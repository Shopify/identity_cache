# frozen_string_literal: true

module IdentityCache
  module Cached
    module Prefetcher
      ASSOCIATION_FETCH_EVENT = "association_fetch.identity_cache"

      class << self
        def prefetch(klass, associations, records, load_strategy: LoadStrategy::Eager)
          return if (records = records.to_a).empty?

          case associations
          when Symbol
            fetch_association(load_strategy, klass, associations, records) {}
          when Array
            load_strategy.lazy_load do |lazy_loader|
              associations.each do |association|
                prefetch(klass, association, records, load_strategy: lazy_loader)
              end
            end
          when Hash
            load_strategy.lazy_load do |lazy_loader|
              associations.each do |association, sub_associations|
                fetch_association(lazy_loader, klass, association, records) do |next_level_records|
                  if sub_associations.present?
                    association_class = klass.reflect_on_association(association).klass
                    prefetch(association_class, sub_associations, next_level_records, load_strategy: lazy_loader)
                  end
                end
              end
            end
          else
            raise TypeError, "Invalid associations class #{associations.class}"
          end
        end

        private

        def fetch_association(load_strategy, klass, association, records, &block)
          unless klass.should_use_cache?
            preload_scope = nil
            ActiveRecord::Associations::Preloader.new.preload(records, association, preload_scope)
            return yield
          end

          cached_association = klass.cached_association(association)
          cached_association.fetch_async(load_strategy, records, &block)
        end
      end
    end
  end
end
