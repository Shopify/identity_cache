module IdentityCache
  module QueryAPI
    extend ActiveSupport::Concern

    included do |base|
      base.after_commit :expire_cache
      if Gem::Version.new(ActiveRecord::VERSION::STRING) < Gem::Version.new("4.0.4")
        base.after_touch :expire_cache
      end
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
      def fetch_by_id(id)
        return unless id
        raise NotImplementedError, "fetching needs the primary index enabled" unless primary_cache_index_enabled
        if IdentityCache.should_cache?

          require_if_necessary do
            object = nil
            coder = IdentityCache.fetch(rails_cache_key(id)){ coder_from_record(object = resolve_cache_miss(id)) }
            object ||= record_from_coder(coder)
            IdentityCache.logger.error "[IDC id mismatch] fetch_by_id_requested=#{id} fetch_by_id_got=#{object.id} for #{object.inspect[(0..100)]} " if object && object.id != id.to_i
            object
          end

        else
          self.where(id: id).first
        end
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.find, will raise ActiveRecord::RecordNotFound exception
      # if id is not in the cache or the db.
      def fetch(id)
        fetch_by_id(id) or raise(ActiveRecord::RecordNotFound, "Couldn't find #{self.name} with ID=#{id}")
      end

      # Default fetcher added to the model on inclusion, if behaves like
      # ActiveRecord::Base.find_all_by_id
      def fetch_multi(*ids)
        raise NotImplementedError, "fetching needs the primary index enabled" unless primary_cache_index_enabled
        options = ids.extract_options!
        records = if IdentityCache.should_cache?
          require_if_necessary do
            cache_keys = ids.map {|id| rails_cache_key(id) }
            key_to_id_map = Hash[ cache_keys.zip(ids) ]
            key_to_record_map = {}

            coders_by_key = IdentityCache.fetch_multi(*cache_keys) do |unresolved_keys|
              ids = unresolved_keys.map {|key| key_to_id_map[key] }
              records = find_batch(ids)
              found_records = records.compact
              found_records.each{ |record| record.send(:populate_association_caches) }
              key_to_record_map = found_records.index_by{ |record| rails_cache_key(record.id) }
              records.map {|record| coder_from_record(record) }
            end

            cache_keys.map{ |key| key_to_record_map[key] || record_from_coder(coders_by_key[key]) }
          end
        else
          find_batch(ids)
        end
        records.compact!
        prefetch_associations(options[:includes], records) if options[:includes]
        records
      end

      private

      def record_from_coder(coder) #:nodoc:
        if coder.present? && coder.has_key?(:class)
          record = coder[:class].allocate
          unless coder[:class].serialized_attributes.empty?
            coder = coder.dup
            coder['attributes'] = coder['attributes'].dup
          end
          if record.class._initialize_callbacks.empty?
            record.instance_eval do
              @attributes = self.class.initialize_attributes(coder['attributes'])
              @relation = nil

              @attributes_cache, @previously_changed, @changed_attributes = {}, {}, {}
              @association_cache = {}
              @aggregation_cache = {}
              @_start_transaction_state = {}
              @readonly = @destroyed = @marked_for_destruction = false
              @new_record = false
              @column_types = self.class.column_types if self.class.respond_to?(:column_types)
            end
          else
            record.init_with(coder)
          end

          coder[:associations].each {|name, value| set_embedded_association(record, name, value) } if coder.has_key?(:associations)
          coder[:normalized_has_many].each {|name, ids| record.instance_variable_set(:"@#{record.class.cached_has_manys[name][:ids_variable_name]}", ids) } if coder.has_key?(:normalized_has_many)
          record
        end
      end

      def set_embedded_association(record, association_name, coder_or_array) #:nodoc:
        value = if IdentityCache.unmap_cached_nil_for(coder_or_array).nil?
          nil
        elsif (reflection = record.class.reflect_on_association(association_name)).collection?
          association = reflection.association_class.new(record, reflection)
          association.target = coder_or_array.map {|e| record_from_coder(e) }
          association.target.each {|e| association.set_inverse_instance(e) }
          association
        else
          record_from_coder(coder_or_array)
        end
        variable_name = record.class.send(:recursively_embedded_associations)[association_name][:records_variable_name]
        record.instance_variable_set(:"@#{variable_name}", IdentityCache.map_cached_nil_for(value))
      end

      def get_embedded_association(record, association, options) #:nodoc:
        embedded_variable = record.instance_variable_get(:"@#{options[:records_variable_name]}")
        if IdentityCache.unmap_cached_nil_for(embedded_variable).nil?
          nil
        elsif record.class.reflect_on_association(association).collection?
          embedded_variable.map {|e| coder_from_record(e) }
        else
          coder_from_record(embedded_variable)
        end
      end

      def coder_from_record(record) #:nodoc:
        unless record.nil?
          coder = {:class => record.class }
          record.encode_with(coder)
          add_cached_associations_to_coder(record, coder)
          coder
        end
      end

      def add_cached_associations_to_coder(record, coder)
        klass = record.class
        if klass.include?(IdentityCache)
          if (recursively_embedded_associations = klass.send(:recursively_embedded_associations)).present?
            coder[:associations] = recursively_embedded_associations.each_with_object({}) do |(name, options), hash|
              hash[name] = IdentityCache.map_cached_nil_for(get_embedded_association(record, name, options))
            end
          end
          if (cached_has_manys = klass.cached_has_manys).present?
            coder[:normalized_has_many] = cached_has_manys.each_with_object({}) do |(name, options), hash|
              hash[name] = record.instance_variable_get(:"@#{options[:ids_variable_name]}") unless options[:embed] == true
            end
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
        object = self.includes(cache_fetch_includes).where(id: id).try(:first)
        object.send(:populate_association_caches) if object
        object
      end

      def recursively_embedded_associations
        all_cached_associations.select do |cached_association, options|
          options[:embed] == true
        end
      end

      def all_cached_associations
        (cached_has_manys || {}).merge(cached_has_ones || {}).merge(cached_belongs_tos || {})
      end

      def embedded_associations
        all_cached_associations.select do |cached_association, options|
          options[:embed]
        end
      end

      def cache_fetch_includes
        associations_for_identity_cache = recursively_embedded_associations.map do |child_association, options|
          child_class = reflect_on_association(child_association).try(:klass)

          child_includes = nil
          if child_class.respond_to?(:cache_fetch_includes, true)
            child_includes = child_class.send(:cache_fetch_includes)
          end

          if child_includes.blank?
            child_association
          else
            { child_association => child_includes }
          end
        end

        associations_for_identity_cache.compact
      end

      def find_batch(ids)
        @id_column ||= columns.detect {|c| c.name == "id"}
        ids = ids.map{ |id| @id_column.type_cast(id) }
        records = where('id IN (?)', ids).includes(cache_fetch_includes).to_a
        records_by_id = records.index_by(&:id)
        ids.map{ |id| records_by_id[id] }
      end

      def prefetch_associations(associations, records)
        associations = hashify_includes_structure(associations)

        associations.each do |association, sub_associations|
          case
          when details = cached_has_manys[association]

            if details[:embed] == true
              child_records = records.map(&details[:cached_accessor_name].to_sym).flatten
            else
              ids_to_parent_record = records.each_with_object({}) do |record, hash|
                child_ids = record.send(details[:cached_ids_name])
                child_ids.each do |child_id|
                  hash[child_id] = record
                end
              end

              parent_record_to_child_records = Hash.new { |h, k| h[k] = [] }
              child_records = details[:association_class].fetch_multi(*ids_to_parent_record.keys)
              child_records.each do |child_record|
                parent_record = ids_to_parent_record[child_record.id]
                parent_record_to_child_records[parent_record] << child_record
              end

              parent_record_to_child_records.each do |parent_record, child_records|
                parent_record.send(details[:prepopulate_method_name], child_records)
              end
            end

            next_level_records = child_records

          when details = cached_belongs_tos[association]
            if details[:embed] == true
              raise ArgumentError.new("Embedded belongs_to associations do not support prefetching yet.")
            else
              ids_to_child_record = records.each_with_object({}) do |child_record, hash|
                parent_id = child_record.send(details[:foreign_key])
                hash[parent_id] = child_record if parent_id.present?
              end
              parent_records = details[:association_class].fetch_multi(*ids_to_child_record.keys)
              parent_records.each do |parent_record|
                child_record = ids_to_child_record[parent_record.id]
                child_record.send(details[:prepopulate_method_name], parent_record)
              end
            end

            next_level_records = parent_records

          when details = cached_has_ones[association]
            if details[:embed] == true
              parent_records = records.map(&details[:cached_accessor_name].to_sym)
            else
              raise ArgumentError.new("Non-embedded has_one associations do not support prefetching yet.")
            end

            next_level_records = parent_records

          else
            raise ArgumentError.new("Unknown cached association #{association} listed for prefetching")
          end

          if details && details[:association_class].respond_to?(:prefetch_associations, true)
            details[:association_class].send(:prefetch_associations, sub_associations, next_level_records)
          end
        end
      end

      def hashify_includes_structure(structure)
        case structure
        when nil
          {}
        when Symbol
          {structure => []}
        when Hash
          structure.clone
        when Array
          structure.each_with_object({}) do |member, hash|
            case member
            when Hash
              hash.merge!(member)
            when Symbol
              hash[member] = []
            end
          end
        end
      end
    end

    private

    def populate_association_caches # :nodoc:
      self.class.send(:embedded_associations).each do |cached_association, options|
        send(options[:population_method_name])
        reflection = options[:embed] == true && self.class.reflect_on_association(cached_association)
        if reflection && reflection.klass.respond_to?(:cached_has_manys)
          child_objects = Array.wrap(send(options[:cached_accessor_name]))
          child_objects.each{ |child| child.send(:populate_association_caches) }
        end
      end
    end

    def fetch_recursively_cached_association(ivar_name, association_name) # :nodoc:
      ivar_full_name = :"@#{ivar_name}"
      if IdentityCache.should_cache?
        populate_recursively_cached_association(ivar_name, association_name)
        assoc = IdentityCache.unmap_cached_nil_for(instance_variable_get(ivar_full_name))
        assoc.is_a?(ActiveRecord::Associations::CollectionAssociation) ? assoc.reader : assoc
      else
        send(association_name.to_sym)
      end
    end

    def populate_recursively_cached_association(ivar_name, association_name) # :nodoc:
      ivar_full_name = :"@#{ivar_name}"

      value = instance_variable_get(ivar_full_name)
      return value unless value.nil?

      loaded_association = send(association_name)

      instance_variable_set(ivar_full_name, IdentityCache.map_cached_nil_for(loaded_association))
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

    def expire_secondary_indexes # :nodoc:
      return unless self.class.primary_cache_index_enabled
      cache_indexes.try(:each) do |fields|
        if self.destroyed?
          IdentityCache.cache.delete(secondary_cache_index_key_for_previous_values(fields))
        else
          new_cache_index_key = secondary_cache_index_key_for_current_values(fields)
          IdentityCache.cache.delete(new_cache_index_key)

          if !was_new_record?
            old_cache_index_key = secondary_cache_index_key_for_previous_values(fields)
            IdentityCache.cache.delete(old_cache_index_key) unless old_cache_index_key == new_cache_index_key
          end
        end
      end
    end

    def expire_attribute_indexes # :nodoc:
      cache_attributes.try(:each) do |(attribute, fields)|
        unless was_new_record?
          old_cache_attribute_key = attribute_cache_key_for_attribute_and_previous_values(attribute, fields)
          IdentityCache.cache.delete(old_cache_attribute_key)
        end
        new_cache_attribute_key = attribute_cache_key_for_attribute_and_current_values(attribute, fields)
        if new_cache_attribute_key != old_cache_attribute_key
          IdentityCache.cache.delete(new_cache_attribute_key)
        end
      end
    end

    def expire_cache # :nodoc:
      expire_primary_index
      expire_secondary_indexes
      expire_attribute_indexes
      true
    end

    def was_new_record? # :nodoc:
      !destroyed? && transaction_changed_attributes.has_key?('id') && transaction_changed_attributes['id'].nil?
    end
  end
end
