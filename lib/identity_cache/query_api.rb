# frozen_string_literal: true
module IdentityCache
  module QueryAPI
    extend ActiveSupport::Concern

    included do |base|
      base.after_commit(:expire_cache)
    end

    module ClassMethods
      # Prefetches cached associations on a collection of records
      def prefetch_associations(includes, records)
        Cached::Prefetcher.prefetch(self, includes, records)
      end

      # @api private
      def cached_association(name) # :nodoc:
        cached_has_manys[name] || cached_has_ones[name] || cached_belongs_tos.fetch(name)
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
            record.send(:set_embedded_association, association_name, target)
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

      def all_cached_associations
        cached_has_manys.merge(cached_has_ones).merge(cached_belongs_tos)
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

    def fetch_recursively_cached_association(ivar_name, dehydrated_ivar_name, association_name) # :nodoc:
      assoc = association(association_name)

      IdentityCache::Tracking.track_association_accessed(self, association_name)
      if assoc.klass.should_use_cache? && !assoc.loaded?
        if instance_variable_defined?(ivar_name)
          instance_variable_get(ivar_name)
        elsif instance_variable_defined?(dehydrated_ivar_name)
          associated_records = hydrate_association_target(assoc.klass, instance_variable_get(dehydrated_ivar_name))
          set_embedded_association(association_name, associated_records)
          remove_instance_variable(dehydrated_ivar_name)
          instance_variable_set(ivar_name, associated_records)
        else
          assoc.load_target
        end
      else
        assoc.load_target
      end
    end

    def hydrate_association_target(associated_class, dehydrated_value) # :nodoc:
      dehydrated_value = IdentityCache.unmap_cached_nil_for(dehydrated_value)
      if dehydrated_value.is_a?(Array)
        dehydrated_value.map { |coder| Encoder.decode(coder, associated_class) }
      else
        Encoder.decode(dehydrated_value, associated_class)
      end
    end

    def set_embedded_association(association_name, association_target) #:nodoc:
      model = self.class
      cached_association = model.cached_association(association_name)

      set_inverse_of_cached_association(cached_association, association_target)

      instance_variable_set(cached_association.records_variable_name, association_target)
    end

    def set_inverse_of_cached_association(cached_association, association_target)
      return if association_target.nil?
      associated_class = cached_association.reflection.klass
      inverse_name = cached_association.inverse_name
      inverse_cached_association = associated_class.cached_belongs_tos[inverse_name]
      return unless inverse_cached_association

      if association_target.is_a?(Array)
        association_target.each do |child_record|
          child_record.instance_variable_set(
            inverse_cached_association.records_variable_name, self
          )
        end
      else
        association_target.instance_variable_set(
          inverse_cached_association.records_variable_name, self
        )
      end
    end

    def expire_attribute_indexes # :nodoc:
      cache_indexes.each do |cached_attribute|
        cached_attribute.expire(self)
      end
    end
  end
end
