# frozen_string_literal: true
module IdentityCache
  module WithPrimaryIndex
    extend ActiveSupport::Concern

    include WithoutPrimaryIndex

    def expire_cache
      expire_primary_index
      super
    end

    # @api private
    def expire_primary_index # :nodoc:
      self.class.expire_primary_key_cache_index(id)
    end

    # @api private
    def primary_cache_index_key # :nodoc:
      self.class.rails_cache_key(id)
    end

    module ClassMethods
      def primary_cache_index_enabled
        true
      end

      # Declares a new index in the cache for the class where IdentityCache was
      # included.
      #
      # IdentityCache will add a fetch_by_field1_and_field2_and_...field for every
      # index.
      #
      # == Example:
      #
      #  class Product
      #    include IdentityCache
      #    cache_index :name, :vendor
      #  end
      #
      # Will add Product.fetch_by_name_and_vendor
      #
      # == Parameters
      #
      # +fields+ Array of symbols or strings representing the fields in the index
      #
      # == Options
      # * unique: if the index would only have unique values. Default is false
      #
      def cache_index(*fields, unique: false)
        cache_attribute_by_alias('primary_key', 'id', by: fields, unique: unique)

        field_list = fields.join("_and_")
        arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')

        if unique
          instance_eval(<<-CODE, __FILE__, __LINE__ + 1)
            def fetch_by_#{field_list}(#{arg_list}, includes: nil)
              id = fetch_id_by_#{field_list}(#{arg_list})
              id && fetch_by_id(id, includes: includes)
            end

            # exception throwing variant
            def fetch_by_#{field_list}!(#{arg_list}, includes: nil)
              fetch_by_#{field_list}(#{arg_list}, includes: includes) or raise ActiveRecord::RecordNotFound
            end
          CODE
        else
          instance_eval(<<-CODE, __FILE__, __LINE__ + 1)
            def fetch_by_#{field_list}(#{arg_list}, includes: nil)
              ids = fetch_id_by_#{field_list}(#{arg_list})
              ids.empty? ? ids : fetch_multi(ids, includes: includes)
            end
          CODE
        end

        if fields.length == 1
          instance_eval(<<-CODE, __FILE__, __LINE__ + 1)
            def fetch_multi_by_#{field_list}(index_values, includes: nil)
              ids = fetch_multi_id_by_#{field_list}(index_values).values.flatten(1)
              return ids if ids.empty?
              fetch_multi(ids, includes: includes)
            end
          CODE
        end
      end

      # Similar to ActiveRecord::Base#exists? will return true if the id can be
      # found in the cache or in the DB.
      def exists_with_identity_cache?(id)
        !!fetch_by_id(id)
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.where(id: id).first
      def fetch_by_id(id, includes: nil)
        ensure_base_model
        raise_if_scoped
        id = type_for_attribute(primary_key).cast(id)
        return unless id
        record = if should_use_cache?
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
        fetch_by_id(id, includes: includes) || raise(
          ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}"
        )
      end

      # Default fetcher added to the model on inclusion, if behaves like
      # ActiveRecord::Base.find_all_by_id
      def fetch_multi(*ids, includes: nil)
        ensure_base_model
        raise_if_scoped
        ids.flatten!(1)
        id_type = type_for_attribute(primary_key)
        ids.map! { |id| id_type.cast(id) }.compact!
        records = if should_use_cache?
          cache_keys = ids.map { |id| rails_cache_key(id) }
          key_to_id_map = Hash[cache_keys.zip(ids)]
          key_to_record_map = {}

          coders_by_key = IdentityCache.fetch_multi(cache_keys) do |unresolved_keys|
            ids = unresolved_keys.map { |key| key_to_id_map[key] }
            records = find_batch(ids)
            key_to_record_map = records.compact.index_by { |record| rails_cache_key(record.id) }
            records.map { |record| Encoder.encode(record) }
          end

          cache_keys.map do |key|
            key_to_record_map[key] || Encoder.decode(coders_by_key[key], self)
          end
        else
          find_batch(ids)
        end
        records.compact!
        prefetch_associations(includes, records) if includes
        records
      end

      # Invalidates the primary cache index for the associated record. Will not invalidate cached attributes.
      def expire_primary_key_cache_index(id)
        id = type_for_attribute(primary_key).cast(id)
        IdentityCache.cache.delete(rails_cache_key(id))
      end

      # @api private
      def rails_cache_key(id)
        "#{prefixed_rails_cache_key}#{id}"
      end

      private

      def rails_cache_key_prefix
        @rails_cache_key_prefix ||= IdentityCache::CacheKeyGeneration.denormalized_schema_hash(self)
      end

      def prefixed_rails_cache_key
        "#{rails_cache_key_namespace}blob:#{base_class.name}:#{rails_cache_key_prefix}:"
      end

      def resolve_cache_miss(id)
        record = includes(cache_fetch_includes).where(primary_key => id).take
        setup_embedded_associations_on_miss([record]) if record
        record
      end

      def find_batch(ids)
        return [] if ids.empty?

        @id_column ||= columns.detect { |c| c.name == primary_key }
        ids = ids.map { |id| connection.type_cast(id, @id_column) }
        records = where(primary_key => ids).includes(cache_fetch_includes).to_a
        setup_embedded_associations_on_miss(records)
        records_by_id = records.index_by(&:id)
        ids.map { |id| records_by_id[id] }
      end
    end
  end
end
