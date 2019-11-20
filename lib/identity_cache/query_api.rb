# frozen_string_literal: true
module IdentityCache
  module QueryAPI
    extend ActiveSupport::Concern

    included do |base|
      base.after_commit(:expire_cache)
    end

    module ClassMethods
      # Similar to ActiveRecord::Base#exists? will return true if the id can be
      # found in the cache or in the DB.
      def exists_with_identity_cache?(id)
        unless primary_cache_index_enabled
          raise NotImplementedError, "exists_with_identity_cache? needs the primary index enabled"
        end
        !!fetch_by_id(id)
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.where(id: id).first
      def fetch_by_id(id, includes: nil)
        ensure_base_model
        raise_if_scoped
        raise NotImplementedError, "fetching needs the primary index enabled" unless primary_cache_index_enabled
        id = type_for_attribute(primary_key).cast(id)
        return unless id

        record = cached_record_fetcher.fetch(id)

        prefetch_associations(includes, [record]) if record && includes
        record
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.find, will raise ActiveRecord::RecordNotFound exception
      # if id is not in the cache or the db.
      def fetch(id, includes: nil)
        fetch_by_id(id, includes: includes) or raise(
          ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}"
        )
      end

      # Default fetcher added to the model on inclusion, if behaves like
      # ActiveRecord::Base.find_all_by_id
      def fetch_multi(*ids, includes: nil)
        ensure_base_model
        raise_if_scoped
        raise NotImplementedError, "fetching needs the primary index enabled" unless primary_cache_index_enabled
        ids.flatten!(1)
        id_type = type_for_attribute(primary_key)
        ids.map! { |id| id_type.cast(id) }.compact!
        return [] if ids.empty?

        records_by_id = cached_record_fetcher.fetch_multi(ids)
        records = ids.map { |id| records_by_id.fetch(id) }
        records.compact!

        prefetch_associations(includes, records) if includes
        records
      end

      # Prefetches cached associations on a collection of records
      def prefetch_associations(includes, records)
        Cached::Prefetcher.prefetch(self, includes, records)
      end

      # Invalidates the primary cache index for the associated record. Will not invalidate cached attributes.
      def expire_primary_key_cache_index(id)
        return unless primary_cache_index_enabled
        id = type_for_attribute(primary_key).cast(id)
        IdentityCache.cache.delete(rails_cache_key(id))
      end

      # @api private
      def cached_association(name) # :nodoc:
        cached_has_manys[name] || cached_has_ones[name] || cached_belongs_tos.fetch(name)
      end

      # @api private
      def cached_record_fetcher # :nodoc:
        @cached_record_fetcher ||= Cached::RecordFetcher.new(self)
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

      # @api private
      public def recursively_embedded_associations # :nodoc:
        all_cached_associations.select { |_name, association| association.embedded_recursively? }
      end

      def all_cached_associations
        cached_has_manys.merge(cached_has_ones).merge(cached_belongs_tos)
      end

      def embedded_associations
        all_cached_associations.select { |_name, association| association.embedded? }
      end
    end

    # Invalidate the cache data associated with the record.
    def expire_cache
      expire_primary_index
      expire_attribute_indexes
      true
    end

    private

    def fetch_recursively_cached_association(ivar_name, dehydrated_ivar_name, association_name) # :nodoc:
      assoc = association(association_name)

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

    # @api private
    public def set_embedded_association(association_name, association_target) #:nodoc:
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

    def expire_primary_index # :nodoc:
      self.class.expire_primary_key_cache_index(id)
    end

    def expire_attribute_indexes # :nodoc:
      cache_indexes.each do |(attribute, fields, unique)|
        unless was_new_record?
          old_cache_attribute_key = attribute_cache_key_for_attribute_and_previous_values(attribute, fields, unique)
          IdentityCache.cache.delete(old_cache_attribute_key)
        end
        unless destroyed?
          new_cache_attribute_key = attribute_cache_key_for_attribute_and_current_values(attribute, fields, unique)
          if new_cache_attribute_key != old_cache_attribute_key
            IdentityCache.cache.delete(new_cache_attribute_key)
          end
        end
      end
    end

    def was_new_record? # :nodoc:
      pk = self.class.primary_key
      !destroyed? && transaction_changed_attributes.has_key?(pk) && transaction_changed_attributes[pk].nil?
    end
  end
end
