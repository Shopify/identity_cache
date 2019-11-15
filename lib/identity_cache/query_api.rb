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
        record = if should_use_cache?
          require_if_necessary do
            object = nil
            coder  = IdentityCache.fetch(rails_cache_key(id)) do
              Encoder.encode(object = resolve_cache_miss(id))
            end
            object ||= Encoder.decode(coder, self)
            if object && object.id != id
              IdentityCache.logger.error(
                <<~MSG.squish
                  [IDC id mismatch] fetch_by_id_requested=#{id}
                  fetch_by_id_got=#{object.id}
                  for #{object.inspect[(0..100)]}
                MSG
              )
            end
            object
          end
        else
          resolve_cache_miss(id)
        end
        prefetch_associations(includes, [record]) if record && includes
        record
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.find, will raise ActiveRecord::RecordNotFound exception
      # if id is not in the cache or the db.
      def fetch(id, includes: nil)
        fetch_by_id(id, includes: includes) or raise(
          ActiveRecord::RecordNotFound, "Couldn't find #{self.name} with ID=#{id}"
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
        records = if should_use_cache?
          require_if_necessary do
            cache_keys = ids.map {|id| rails_cache_key(id) }
            key_to_id_map = Hash[ cache_keys.zip(ids) ]
            key_to_record_map = {}

            coders_by_key = IdentityCache.fetch_multi(cache_keys) do |unresolved_keys|
              ids = unresolved_keys.map {|key| key_to_id_map[key] }
              records = find_batch(ids)
              key_to_record_map = records.compact.index_by{ |record| rails_cache_key(record.id) }
              records.map { |record| Encoder.encode(record) }
            end

            cache_keys.map do |key|
              key_to_record_map[key] || Encoder.decode(coders_by_key[key], self)
            end
          end
        else
          find_batch(ids)
        end
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

      def require_if_necessary #:nodoc:
        # mem_cache_store returns raw value if unmarshal fails
        rval = yield
        case rval
        when String
          rval = Marshal.load(rval)
        when Array
          rval.map!{ |v| v.kind_of?(String) ? Marshal.load(v) : v }
        end
        rval
      rescue ArgumentError => e
        if e.message =~ /undefined [\w\/]+ (\w+)/
          ok = Kernel.const_get($1) rescue nil
          retry if ok
        end
        raise
      end

      def resolve_cache_miss(id)
        record = self.includes(cache_fetch_includes).where(primary_key => id).take
        setup_embedded_associations_on_miss([record]) if record
        record
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
        ids_by_parent = Hash.new{ |hash, key| hash[key] = [] }
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
        readonly: IdentityCache.fetch_read_only_records && should_use_cache?
      )
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
          child_records = records.flat_map(&cached_association.cached_accessor_name.to_sym).compact
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

      def cached_association(name)
        cached_has_manys[name] || cached_has_ones[name] || cached_belongs_tos.fetch(name)
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
        all_cached_associations.select { |name, association| association.embedded_recursively? }
      end

      def all_cached_associations
        cached_has_manys.merge(cached_has_ones).merge(cached_belongs_tos)
      end

      def embedded_associations
        all_cached_associations.select { |name, association| association.embedded? }
      end

      def cache_fetch_includes
        associations_for_identity_cache = recursively_embedded_associations.map do |child_association, options|
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

      def find_batch(ids)
        return [] if ids.empty?

        @id_column ||= columns.detect {|c| c.name == primary_key}
        ids = ids.map{ |id| connection.type_cast(id, @id_column) }
        records = where(primary_key => ids).includes(cache_fetch_includes).to_a
        setup_embedded_associations_on_miss(records)
        records_by_id = records.index_by(&:id)
        ids.map{ |id| records_by_id[id] }
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

    def set_embedded_association(association_name, association_target) #:nodoc:
      model = self.class
      cached_association = model.send(:cached_association, association_name)

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
