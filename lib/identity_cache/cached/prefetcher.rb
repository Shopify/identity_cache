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

          if (cached_has_many = klass.cached_has_manys[association])
            fetch_has_many(cached_has_many, records)
          elsif (cached_belongs_to = klass.cached_belongs_tos[association])
            fetch_belongs_to(cached_belongs_to, records)
          elsif (cached_has_one = klass.cached_has_ones[association])
            fetch_has_one(cached_has_one, records)
          else
            raise ArgumentError, "Unknown cached association #{association} listed for prefetching"
          end
        end

        def fetch_has_many(cached_has_many, records)
          prefetch_embedded(cached_has_many, records)

          if cached_has_many.embedded_recursively?
            child_records = records.flat_map(&cached_has_many.cached_accessor_name.to_sym)
          else
            ids_to_parent_record = records.each_with_object({}) do |record, hash|
              child_ids = record.send(cached_has_many.cached_ids_name)
              child_ids.each do |child_id|
                hash[child_id] = record
              end
            end

            parent_record_to_child_records = Hash.new { |h, k| h[k] = [] }
            child_records = cached_has_many.reflection.klass.fetch_multi(*ids_to_parent_record.keys)
            child_records.each do |child_record|
              parent_record = ids_to_parent_record[child_record.id]
              parent_record_to_child_records[parent_record] << child_record
            end

            parent_record_to_child_records.each do |parent, children|
              parent.instance_variable_set(cached_has_many.records_variable_name, children)
            end
          end

          child_records
        end

        def fetch_has_one(cached_has_one, records)
          if cached_has_one.embedded_recursively?
            prefetch_embedded(cached_has_one, records)
            parent_records = records.map(&cached_has_one.cached_accessor_name.to_sym).compact
          else
            ids_to_parent_record = records.each_with_object({}) do |record, hash|
              child_id = record.send(cached_has_one.cached_id_name)
              hash[child_id] = record if child_id
            end

            parent_record_to_child_record = {}
            child_records = cached_has_one.reflection.klass.fetch_multi(*ids_to_parent_record.keys)
            child_records.each do |child_record|
              parent_record = ids_to_parent_record[child_record.id]
              parent_record_to_child_record[parent_record] ||= child_record
            end

            parent_record_to_child_record.each do |parent, child|
              parent.instance_variable_set(cached_has_one.records_variable_name, child)
            end
          end

          parent_records
        end

        def fetch_belongs_to(cached_belongs_to, records)
          if cached_belongs_to.embedded_recursively?
            raise ArgumentError, "Embedded belongs_to associations do not support prefetching yet."
          else
            reflection = cached_belongs_to.reflection
            cached_iv_name = cached_belongs_to.records_variable_name
            if reflection.polymorphic?
              types_to_parent_ids = {}

              records.each do |child_record|
                parent_id = child_record.send(reflection.foreign_key)
                next unless parent_id && !child_record.instance_variable_defined?(cached_iv_name)
                parent_type = Object.const_get(child_record.send(reflection.foreign_type)).cached_model
                types_to_parent_ids[parent_type] = {} unless types_to_parent_ids[parent_type]
                types_to_parent_ids[parent_type][parent_id] = child_record
              end

              parent_records = []

              types_to_parent_ids.each do |type, ids_to_child_record|
                type_parent_records = type.fetch_multi(ids_to_child_record.keys)
                type_parent_records.each do |parent_record|
                  child_record = ids_to_child_record[parent_record.id]
                  child_record.instance_variable_set(cached_belongs_to.records_variable_name, parent_record)
                end
                parent_records.append(type_parent_records)
              end
            else
              ids_to_child_record = records.each_with_object({}) do |child_record, hash|
                parent_id = child_record.send(reflection.foreign_key)
                if parent_id && !child_record.instance_variable_defined?(cached_iv_name)
                  hash[parent_id] = child_record
                end
              end
              parent_records = reflection.klass.fetch_multi(ids_to_child_record.keys)
              parent_records.each do |parent_record|
                child_record = ids_to_child_record[parent_record.id]
                child_record.instance_variable_set(cached_belongs_to.records_variable_name, parent_record)
              end
            end
          end

          parent_records
        end

        def prefetch_embedded(cached_association, records)
          # Make the same assumption as ActiveRecord::Associations::Preloader, which is
          # that all the records have the same associations loaded, so we can just check
          # the first record to see if an association is loaded.
          first_record = records.first
          return if first_record.association(cached_association.name).loaded?
          if cached_association.embedded_recursively?
            return if first_record.instance_variable_defined?(cached_association.dehydrated_variable_name)
            return if first_record.instance_variable_defined?(cached_association.records_variable_name)
          elsif first_record.instance_variable_defined?(cached_association.ids_variable_name)
            return
          end
          fetch_embedded(cached_association, records)
        end

        def fetch_embedded(cached_association, records)
          klass = cached_association.reflection.active_record
          associations = klass.send(:embedded_associations)
          return if associations.empty?

          return unless klass.primary_cache_index_enabled

          cached_records_by_id = klass.fetch_multi(records.map(&:id)).index_by(&:id)

          associations.each_value do |association|
            records.each do |record|
              next unless (cached_record = cached_records_by_id[record.id])
              case association
              when Cached::Reference::HasMany
                cached_association = cached_record.public_send(association.cached_ids_name)
                record.instance_variable_set(association.ids_variable_name, cached_association)
              when Cached::Reference::HasOne
                cached_association = cached_record.public_send(association.cached_id_name)
                record.instance_variable_set(association.id_variable_name, cached_association)
              else
                cached_association = cached_record.public_send(association.cached_accessor_name)
                record.instance_variable_set(association.records_variable_name, cached_association)
              end
            end
          end
        end
      end
    end
  end
end
