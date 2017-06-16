module IdentityCache
  module QueryAPI
    extend ActiveSupport::Concern

    included do |base|
      base.after_commit :expire_cache
    end

    module ClassMethods
      # Similar to ActiveRecord::Base#exists? will return true if the id can be
      # found in the cache or in the DB.
      def exists_with_identity_cache?(id)
        raise NotImplementedError, "exists_with_identity_cache? needs the primary index enabled" unless primary_cache_index_enabled
        !!fetch_by_id(id)
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.where(id: id).first
      def fetch_by_id(id, includes: nil)
        ensure_base_model
        raise_if_scoped
        raise NotImplementedError, "fetching needs the primary index enabled" unless primary_cache_index_enabled
        return unless id
        record = if should_use_cache?
          require_if_necessary do
            object = nil
            coder = IdentityCache.fetch(rails_cache_key(id)){ instrumented_coder_from_record(object = resolve_cache_miss(id)) }
            object ||= instrumented_record_from_coder(coder)
            if object && object.id.to_s != id.to_s
              IdentityCache.logger.error "[IDC id mismatch] fetch_by_id_requested=#{id} fetch_by_id_got=#{object.id} for #{object.inspect[(0..100)]}"
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
        fetch_by_id(id, includes: includes) or raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.name} with ID=#{id}")
      end

      # Default fetcher added to the model on inclusion, if behaves like
      # ActiveRecord::Base.find_all_by_id
      def fetch_multi(*ids, includes: nil)
        ensure_base_model
        raise_if_scoped
        raise NotImplementedError, "fetching needs the primary index enabled" unless primary_cache_index_enabled
        ids.flatten!(1)
        records = if should_use_cache?
          require_if_necessary do
            cache_keys = ids.map {|id| rails_cache_key(id) }
            key_to_id_map = Hash[ cache_keys.zip(ids) ]
            key_to_record_map = {}

            coders_by_key = IdentityCache.fetch_multi(cache_keys) do |unresolved_keys|
              ids = unresolved_keys.map {|key| key_to_id_map[key] }
              records = find_batch(ids)
              key_to_record_map = records.compact.index_by{ |record| rails_cache_key(record.id) }
              records.map {|record| instrumented_coder_from_record(record) }
            end

            cache_keys.map{ |key| key_to_record_map[key] || instrumented_record_from_coder(coders_by_key[key]) }
          end
        else
          find_batch(ids)
        end
        records.compact!
        prefetch_associations(includes, records) if includes
        records
      end

      def prefetch_associations(associations, records)
        records = records.to_a
        return if records.empty?

        case associations
        when nil
          # do nothing
        when Symbol
          prefetch_one_association(associations, records)
        when Array
          associations.each do |association|
            prefetch_associations(association, records)
          end
        when Hash
          associations.each do |association, sub_associations|
            next_level_records = prefetch_one_association(association, records)

            if sub_associations.present?
              associated_class = reflect_on_association(association).klass
              associated_class.prefetch_associations(sub_associations, next_level_records)
            end
          end
        else
          raise TypeError, "Invalid associations class #{associations.class}"
        end
        nil
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
          raise UnsupportedAssociationError, "caching association #{self}.#{association_name} scoped with a join isn't supported"
        end
      end

      def instrumented_record_from_coder(coder) #:nodoc:
        return unless coder
        ActiveSupport::Notifications.instrument('identity_cache.hydration', class: coder[:class]) do
          record_from_coder(coder)
        end
      end

      def record_from_coder(coder) #:nodoc:
        if coder
          klass = coder[:class].constantize
          record = klass.instantiate(coder[:attributes].dup)

          coder[:associations].each {|name, value| set_embedded_association(record, name, value) } if coder.has_key?(:associations)
          coder[:association_ids].each {|name, ids| record.instance_variable_set(:"@#{record.class.cached_has_manys[name][:ids_variable_name]}", ids) } if coder.has_key?(:association_ids)
          record.readonly! if IdentityCache.fetch_read_only_records
          record
        end
      end

      def set_inverse_of_cached_has_many(record, association_reflection, child_records)
        associated_class = association_reflection.klass
        inverse_name = record.class.cached_has_manys.fetch(association_reflection.name).fetch(:inverse_name)
        inverse_cached_association = associated_class.cached_belongs_tos[inverse_name]
        return unless inverse_cached_association

        prepopulate_method_name = inverse_cached_association.fetch(:prepopulate_method_name)
        child_records.each { |child_record| child_record.send(prepopulate_method_name, record) }
      end

      def set_embedded_association(record, association_name, coder_or_array) #:nodoc:
        value = if IdentityCache.unmap_cached_nil_for(coder_or_array).nil?
          nil
        elsif (reflection = record.class.reflect_on_association(association_name)).collection?
          associated_records = coder_or_array.map {|e| record_from_coder(e) }
          set_inverse_of_cached_has_many(record, reflection, associated_records)
          associated_records
        else
          record_from_coder(coder_or_array)
        end
        variable_name = record.class.send(:recursively_embedded_associations)[association_name][:records_variable_name]
        record.instance_variable_set(:"@#{variable_name}", value)
      end

      def get_embedded_association(record, association, options) #:nodoc:
        embedded_variable = record.public_send(options.fetch(:cached_accessor_name))
        if embedded_variable.respond_to?(:to_ary)
          embedded_variable.map {|e| coder_from_record(e) }
        else
          coder_from_record(embedded_variable)
        end
      end

      def instrumented_coder_from_record(record) #:nodoc:
        return unless record
        ActiveSupport::Notifications.instrument('identity_cache.dehydration', class: record.class.name) do
          coder_from_record(record)
        end
      end

      def coder_from_record(record) #:nodoc:
        unless record.nil?
          coder = {
            attributes: record.attributes_before_type_cast.dup,
            class: record.class.name,
          }
          add_cached_associations_to_coder(record, coder)
          coder
        end
      end

      def add_cached_associations_to_coder(record, coder)
        klass = record.class
        if (recursively_embedded_associations = klass.send(:recursively_embedded_associations)).present?
          coder[:associations] = recursively_embedded_associations.each_with_object({}) do |(name, options), hash|
            hash[name] = IdentityCache.map_cached_nil_for(get_embedded_association(record, name, options))
          end
        end
        if (cached_has_manys = klass.cached_has_manys).present?
          coder[:association_ids] = cached_has_manys.each_with_object({}) do |(name, options), hash|
            hash[name] = record.instance_variable_get(:"@#{options[:ids_variable_name]}") unless options[:embed] == true
          end
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
        record = self.includes(cache_fetch_includes).reorder(nil).where(primary_key => id).first
        if record
          preload_id_embedded_associations([record])
          record.readonly! if IdentityCache.fetch_read_only_records && should_use_cache?
        end
        record
      end

      def preload_id_embedded_associations(records)
        return if records.empty?
        each_id_embedded_association do |options|
          reflection = options.fetch(:association_reflection)
          child_model = reflection.klass
          scope = child_model.all
          scope = scope.instance_exec(nil, &reflection.scope) if reflection.scope

          pairs = scope.where(reflection.foreign_key => records.map(&:id)).pluck(reflection.foreign_key, reflection.association_primary_key)
          ids_by_parent = Hash.new{ |hash, key| hash[key] = [] }
          pairs.each do |parent_id, child_id|
            ids_by_parent[parent_id] << child_id
          end

          records.each do |parent|
            child_ids = ids_by_parent[parent.id]
            parent.instance_variable_set(:"@#{options.fetch(:ids_variable_name)}", child_ids)
          end
        end
        recursively_embedded_associations.each_value do |options|
          child_model = options.fetch(:association_reflection).klass
          child_records = records.flat_map(&options.fetch(:cached_accessor_name).to_sym).compact
          child_model.send(:preload_id_embedded_associations, child_records)
        end
      end

      def each_id_embedded_association
        cached_has_manys.each_value do |options|
          yield options if options.fetch(:embed) == :ids
        end
      end

      def recursively_embedded_associations
        all_cached_associations.select do |cached_association, options|
          options[:embed] == true
        end
      end

      def all_cached_associations
        cached_has_manys.merge(cached_has_ones).merge(cached_belongs_tos)
      end

      def embedded_associations
        all_cached_associations.select do |cached_association, options|
          options[:embed]
        end
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
        records.each(&:readonly!) if IdentityCache.fetch_read_only_records && should_use_cache?
        preload_id_embedded_associations(records)
        records_by_id = records.index_by(&:id)
        ids.map{ |id| records_by_id[id] }
      end

      def fetch_embedded_associations(records)
        associations = embedded_associations
        return if associations.empty?

        return unless primary_cache_index_enabled

        cached_records_by_id = fetch_multi(records.map(&:id)).index_by(&:id)

        associations.each_value do |options|
          records.each do |record|
            next unless cached_record = cached_records_by_id[record.id]
            if options[:embed] == :ids
              cached_association = cached_record.public_send(options.fetch(:cached_ids_name))
              record.instance_variable_set(:"@#{options.fetch(:ids_variable_name)}", cached_association)
            else
              cached_association = cached_record.public_send(options.fetch(:cached_accessor_name))
              record.instance_variable_set(:"@#{options.fetch(:records_variable_name)}", cached_association)
            end
          end
        end
      end

      def prefetch_embedded_association(records, association, details)
        # Make the same assumption as ActiveRecord::Associations::Preloader, which is
        # that all the records have the same associations loaded, so we can just check
        # the first record to see if an association is loaded.
        first_record = records.first
        return if first_record.association(association).loaded?
        iv_name_key = details[:embed] == true ? :records_variable_name : :ids_variable_name
        return if first_record.instance_variable_defined?(:"@#{details[iv_name_key]}")
        fetch_embedded_associations(records)
      end

      def prefetch_one_association(association, records)
        unless records.first.class.should_use_cache?
          ActiveRecord::Associations::Preloader.new.preload(records, association)
          return
        end

        case
        when details = cached_has_manys[association]
          prefetch_embedded_association(records, association, details)
          if details[:embed] == true
            child_records = records.flat_map(&details[:cached_accessor_name].to_sym)
          else
            ids_to_parent_record = records.each_with_object({}) do |record, hash|
              child_ids = record.send(details[:cached_ids_name])
              child_ids.each do |child_id|
                hash[child_id] = record
              end
            end

            parent_record_to_child_records = Hash.new { |h, k| h[k] = [] }
            child_records = details[:association_reflection].klass.fetch_multi(*ids_to_parent_record.keys)
            child_records.each do |child_record|
              parent_record = ids_to_parent_record[child_record.id]
              parent_record_to_child_records[parent_record] << child_record
            end

            parent_record_to_child_records.each do |parent, children|
              parent.send(details[:prepopulate_method_name], children)
            end
          end

          next_level_records = child_records

        when details = cached_belongs_tos[association]
          if details[:embed] == true
            raise ArgumentError.new("Embedded belongs_to associations do not support prefetching yet.")
          else
            reflection = details[:association_reflection]
            if reflection.polymorphic?
              raise ArgumentError.new("Polymorphic belongs_to associations do not support prefetching yet.")
            end

            cached_iv_name = :"@#{details.fetch(:records_variable_name)}"
            ids_to_child_record = records.each_with_object({}) do |child_record, hash|
              parent_id = child_record.send(reflection.foreign_key)
              if parent_id && !child_record.instance_variable_defined?(cached_iv_name)
                hash[parent_id] = child_record
              end
            end
            parent_records = reflection.klass.fetch_multi(ids_to_child_record.keys)
            parent_records.each do |parent_record|
              child_record = ids_to_child_record[parent_record.id]
              child_record.send(details[:prepopulate_method_name], parent_record)
            end
          end

          next_level_records = parent_records

        when details = cached_has_ones[association]
          if details[:embed] == true
            prefetch_embedded_association(records, association, details)
            parent_records = records.map(&details[:cached_accessor_name].to_sym).compact
          else
            raise ArgumentError.new("Non-embedded has_one associations do not support prefetching yet.")
          end

          next_level_records = parent_records

        else
          raise ArgumentError.new("Unknown cached association #{association} listed for prefetching")
        end
        next_level_records
      end
    end

    private

    def fetch_recursively_cached_association(ivar_name, association_name) # :nodoc:
      ivar_full_name = :"@#{ivar_name}"
      assoc = association(association_name)

      if assoc.klass.should_use_cache?
        if instance_variable_defined?(ivar_full_name)
          instance_variable_get(ivar_full_name)
        else
          cached_assoc = assoc.load_target
          if IdentityCache.fetch_read_only_records
            cached_assoc = readonly_copy(cached_assoc)
          end
          instance_variable_set(ivar_full_name, cached_assoc)
        end
      else
        assoc.load_target
      end
    end

    def expire_primary_index # :nodoc:
      return unless self.class.primary_cache_index_enabled

      IdentityCache.logger.debug do
        extra_keys =
          if respond_to?(:updated_at)
            old_updated_at = old_values_for_fields([:updated_at]).first
            "expiring_last_updated_at=#{old_updated_at}"
          else
            ""
          end

        "[IdentityCache] expiring=#{self.class.name} expiring_id=#{id} #{extra_keys}"
      end

      IdentityCache.cache.delete(primary_cache_index_key)
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

    def expire_cache # :nodoc:
      expire_primary_index
      expire_attribute_indexes
      true
    end

    def was_new_record? # :nodoc:
      pk = self.class.primary_key
      !destroyed? && transaction_changed_attributes.has_key?(pk) && transaction_changed_attributes[pk].nil?
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
