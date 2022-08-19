# frozen_string_literal: true

module IdentityCache
  module QueryAPI
    extend ActiveSupport::Concern

    module ClassMethods
      # Prefetches cached associations on a collection of records
      def prefetch_associations(includes, records)
        Cached::Prefetcher.prefetch(self, includes, records)
      end

      # @api private
      def cached_association(name) # :nodoc:
        cached_has_manys[name] || cached_has_ones[name] || cached_belongs_tos.fetch(name)
      end

      # @api private
      def all_cached_associations # :nodoc:
        cached_has_manys.merge(cached_has_ones).merge(cached_belongs_tos)
      end

      private

      def raise_if_scoped
        if current_scope
          IdentityCache.logger.error("#{name} has scope: #{current_scope.to_sql} (#{current_scope.values.keys})")
          raise UnsupportedScopeError, "IdentityCache doesn't support rails scopes (#{name})"
        end
      end

      def check_association_scope(association_name)
        association_reflection = reflect_on_association(association_name)
        scope = association_reflection.scope
        if scope && !association_reflection.klass.all.instance_exec(&scope).joins_values.empty?
          raise UnsupportedAssociationError, <<~MSG.squish
            caching association #{self}.#{association_name}
            scoped with a join isn't supported
          MSG
        end
      end

      def preload_id_embedded_association(records, cached_association)
        reflection = cached_association.reflection
        child_model = reflection.klass
        scope = child_model.all
        scope = scope.where(reflection.type => base_class.name) if reflection.type
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

      def setup_embedded_associations_on_miss(records,
        readonly: IdentityCache.fetch_read_only_records && should_use_cache?)
        return if records.empty?

        records.each(&:readonly!) if readonly
        each_id_embedded_association do |cached_association|
          preload_id_embedded_association(records, cached_association)
        end
        recursively_embedded_associations.each_value do |cached_association|
          association_reflection = cached_association.reflection
          association_name = association_reflection.name

          # Move the loaded records to the cached association instance variable so they
          # behave the same way if they were loaded from the cache
          records.each do |record|
            association = record.association(association_name)
            target = association.target
            target = readonly_copy(target) if readonly
            cached_association.set_with_inverse(record, target)
            association.reset
            # reset inverse associations
            next unless target && association_reflection.has_inverse?

            inverse_name = association_reflection.inverse_of.name
            if target.is_a?(Array)
              target.each { |child_record| child_record.association(inverse_name).reset }
            else
              target.association(inverse_name).reset
            end
          end

          child_model = association_reflection.klass
          child_records = records.flat_map(&cached_association.cached_accessor_name).compact
          child_model.send(:setup_embedded_associations_on_miss, child_records, readonly: readonly)
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

      def each_id_embedded_association
        cached_has_manys.each_value do |association|
          yield association if association.embedded_by_reference?
        end
        cached_has_ones.each_value do |association|
          yield association if association.embedded_by_reference?
        end
      end

      def recursively_embedded_associations
        all_cached_associations.select { |_name, association| association.embedded_recursively? }
      end

      def embedded_associations
        all_cached_associations.select { |_name, association| association.embedded? }
      end

      def cache_fetch_includes
        associations_for_identity_cache = recursively_embedded_associations.map do |child_association, _options|
          child_class = reflect_on_association(child_association).try(:klass)

          child_includes = child_class.send(:cache_fetch_includes)

          if child_includes.blank?
            child_association
          else
            { child_association => child_includes }
          end
        end

        associations_for_identity_cache.compact
      end
    end

    no_op_callback = proc {}
    included do |base|
      # Make sure there is at least once after_commit callback so that _run_commit_callbacks
      # is called, which is overridden to do an early after_commit callback
      base.after_commit(&no_op_callback)
    end

    # Override the method that is used to call after_commit callbacks so that we can
    # expire the caches before other after_commit callbacks. This way we can avoid stale
    # cache reads that happen from the ordering of callbacks. For example, if an after_commit
    # callback enqueues a background job, then we don't want it to be possible for the
    # background job to run and load data from the cache before it is invalidated.
    def _run_commit_callbacks
      if destroyed? || transaction_changed_attributes.present?
        expire_cache
        expire_parent_caches
      end
      super
    end

    # Invalidate the cache data associated with the record.
    def expire_cache
      expire_attribute_indexes
      true
    end

    # @api private
    def was_new_record? # :nodoc:
      pk = self.class.primary_key
      !destroyed? && transaction_changed_attributes.key?(pk) && transaction_changed_attributes[pk].nil?
    end

    private

    def expire_attribute_indexes # :nodoc:
      cache_indexes.each do |cached_attribute|
        cached_attribute.expire_for_save(self)
      end
    end
  end
end
