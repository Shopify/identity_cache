# frozen_string_literal: true

module IdentityCache
  module Cached
    class RecordFetcher < AbstractFetcher
      attr_accessor :model

      def initialize(model)
        @model = model
      end

      private

      # AbstractFetcher method overrides

      def should_use_cache?
        model.should_use_cache?
      end

      def input_key_to_cache_key(id)
        model.rails_cache_key(id)
      end

      def default_value
        nil
      end

      def encode(record)
        Encoder.encode(record)
      end

      def decode(cache_value)
        Encoder.decode(cache_value, model)
      end

      def load_multi_from_db(ids)
        ids = ids.map { |id| model.connection.type_cast(id, id_column) }
        records = model.where(model.primary_key => ids).includes(db_load_includes).to_a
        self.class.setup_embedded_associations_on_miss(model, records)
        records.index_by(&:id)
      end

      def load_from_db(id)
        record = model.includes(db_load_includes).where(model.primary_key => id).take
        self.class.setup_embedded_associations_on_miss(model, [record]) if record
        record
      end

      # helper methods

      protected

      def db_load_includes
        @db_load_includes ||= begin
          model.recursively_embedded_associations.map do |child_association, _options|
            child_class = model.reflect_on_association(child_association).try(:klass)

            child_includes = child_class.cached_record_fetcher.db_load_includes

            if child_includes.blank?
              child_association
            else
              { child_association => child_includes }
            end
          end
        end
      end

      private

      def id_column
        @id_column ||= model.columns.detect { |c| c.name == model.primary_key }
      end

      class << self
        def preload_id_embedded_association(model, records, cached_association)
          reflection = cached_association.reflection
          child_model = reflection.klass
          scope = child_model.all
          scope = scope.where(reflection.type => model.base_class.name) if reflection.type
          scope = scope.instance_exec(nil, &reflection.scope) if reflection.scope

          pairs = scope.where(reflection.foreign_key => records.map(&:id)).pluck(
            reflection.foreign_key, reflection.association_primary_key
          )
          ids_by_parent = Hash.new { |hash, key| hash[key] = [] }
          pairs.each do |parent_id, child_id|
            ids_by_parent[parent_id] << child_id
          end

          records.each do |parent|
            child_ids = ids_by_parent[parent.id]
            case cached_association
            when Cached::Reference::HasMany
              parent.instance_variable_set(cached_association.ids_variable_name, child_ids)
            when Cached::Reference::HasOne
              parent.instance_variable_set(cached_association.id_variable_name, child_ids.first)
            end
          end
        end

        def each_id_embedded_association(model)
          model.cached_has_manys.each_value do |association|
            yield association if association.embedded_by_reference?
          end
          model.cached_has_ones.each_value do |association|
            yield association if association.embedded_by_reference?
          end
        end

        def setup_embedded_associations_on_miss(model, records,
          readonly: IdentityCache.fetch_read_only_records && model.should_use_cache?
        )
          return if records.empty?
          records.each(&:readonly!) if readonly
          each_id_embedded_association(model) do |cached_association|
            preload_id_embedded_association(model, records, cached_association)
          end
          model.recursively_embedded_associations.each_value do |cached_association|
            association_reflection = cached_association.reflection
            association_name = association_reflection.name

            # Move the loaded records to the cached association instance variable so they
            # behave the same way if they were loaded from the cache
            records.each do |record|
              association = record.association(association_name)
              target = association.target
              target = readonly_copy(target) if readonly
              record.set_embedded_association(association_name, target)
              association.reset
              # reset inverse associations
              if target && association_reflection.has_inverse?
                inverse_name = association_reflection.inverse_of.name
                if target.is_a?(Array)
                  target.each { |child_record| child_record.association(inverse_name).reset }
                else
                  target.association(inverse_name).reset
                end
              end
            end

            child_model = association_reflection.klass
            child_records = records.flat_map(&cached_association.cached_accessor_name).compact
            setup_embedded_associations_on_miss(child_model, child_records, readonly: readonly)
          end
        end

        def readonly_record_copy(record)
          record = record.clone
          record.readonly!
          record
        end

        def readonly_copy(record_or_records)
          if record_or_records.is_a?(Array)
            record_or_records.map { |record| readonly_record_copy(record) }
          elsif record_or_records
            readonly_record_copy(record_or_records)
          end
        end
      end
    end
  end
end
