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
      self.class.cached_primary_index.cache_key(id)
    end

    module ClassMethods
      # @api private
      def cached_primary_index
        @cached_primary_index ||= Cached::PrimaryIndex.new(self)
      end

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
        attribute_proc = -> { primary_key }
        cache_attribute_by_alias(attribute_proc, alias_name: :id, by: fields, unique: unique)

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
              fetch_by_#{field_list}(#{arg_list}, includes: includes) or raise IdentityCache::RecordNotFound
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
        record = cached_primary_index.fetch(id)
        prefetch_associations(includes, [record]) if record && includes
        record
      end

      # Default fetcher added to the model on inclusion, it behaves like
      # ActiveRecord::Base.find, but will raise IdentityCache::RecordNotFound
      # if the id is not in the cache.
      def fetch(id, includes: nil)
        fetch_by_id(id, includes: includes) || raise(
          IdentityCache::RecordNotFound, "Couldn't find #{name} with ID=#{id}"
        )
      end

      # Default fetcher added to the model on inclusion, if behaves like
      # ActiveRecord::Base.find_all_by_id
      def fetch_multi(*ids, includes: nil)
        ensure_base_model
        raise_if_scoped
        ids.flatten!(1)
        records = cached_primary_index.fetch_multi(ids)
        prefetch_associations(includes, records) if includes
        records
      end

      # Invalidates the primary cache index for the associated record. Will not invalidate cached attributes.
      def expire_primary_key_cache_index(id)
        cached_primary_index.expire(id)
      end
    end
  end
end
