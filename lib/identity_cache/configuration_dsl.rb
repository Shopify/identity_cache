# frozen_string_literal: true
module IdentityCache
  module ConfigurationDSL
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute(:cache_indexes)
      base.class_attribute(:cached_has_manys)
      base.class_attribute(:cached_has_ones)
      base.class_attribute(:primary_cache_index_enabled)

      base.cached_has_manys = {}
      base.cached_has_ones = {}
      base.cache_indexes = []
      base.primary_cache_index_enabled = true
    end

    module ClassMethods
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
        raise NotImplementedError, "Cache indexes need an enabled primary index" unless primary_cache_index_enabled
        cache_attribute_by_alias('primary_key', 'id', by: fields, unique: unique)

        field_list = fields.join("_and_")
        arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')

        if unique
          instance_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
            def fetch_by_#{field_list}(#{arg_list}, includes: nil)
              id = fetch_id_by_#{field_list}(#{arg_list})
              id && fetch_by_id(id, includes: includes)

            rescue RangeError
              raise ActiveRecord::RecordNotFound
            end

            # exception throwing variant
            def fetch_by_#{field_list}!(#{arg_list}, includes: nil)
              fetch_by_#{field_list}(#{arg_list}, includes: includes) or raise ActiveRecord::RecordNotFound
            end
          CODE
        else
          instance_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
            def fetch_by_#{field_list}(#{arg_list}, includes: nil)
              ids = fetch_id_by_#{field_list}(#{arg_list})
              ids.empty? ? ids : fetch_multi(ids, includes: includes)
            end
          CODE
        end

        if fields.length == 1
          instance_eval(ruby = <<-CODE, __FILE__, __LINE__ + 1)
            def fetch_multi_by_#{field_list}(index_values, includes: nil)
              ids = fetch_multi_id_by_#{field_list}(index_values).values.flatten(1)
              return ids if ids.empty?
              fetch_multi(ids, includes: includes)
            end
          CODE
        end
      end

      # Will cache an association to the class including IdentityCache.
      # The embed option, if set, will make IdentityCache keep the association
      # values in the same cache entry as the parent.
      #
      # Embedded associations are more effective in offloading database work,
      # however they will increase the size of the cache entries and make the
      # whole entry expire when any of the embedded members change.
      #
      # == Example:
      #   class Product
      #     include IdentityCache
      #     has_many :options
      #     has_many :orders
      #     has_many :buyers
      #     cache_has_many :options, embed: :ids
      #     cache_has_many :orders
      #     cache_has_many :buyers, inverse_name: 'line_item'
      #   end
      #
      # == Parameters
      # +association+ Name of the association being cached as a symbol
      #
      # == Options
      #
      # * embed: If set to true, will cause IdentityCache to keep the
      #   values for this association in the same cache entry as the parent,
      #   instead of its own.
      # * inverse_name: The name of the parent in the association if the name is
      #   not the lowercase pluralization of the parent object's class
      def cache_has_many(association, embed: :ids, inverse_name: nil)
        ensure_base_model
        check_association_for_caching(association)
        reflection = reflect_on_association(association)
        association_class = case embed
        when :ids
          Cached::Reference::HasMany
        when true
          Cached::Recursive::HasMany
        else
          raise NotImplementedError
        end

        cached_has_manys[association] = association_class.new(
          association,
          reflection: reflection,
          inverse_name: inverse_name,
        ).tap(&:build)
      end

      # Will cache an association to the class including IdentityCache.
      # IdentityCache will keep the association values in the same cache entry
      # as the parent.
      #
      # == Example:
      #   class Product
      #     cache_has_one :store, embed: true
      #     cache_has_one :vendor
      #   end
      #
      # == Parameters
      # +association+ Symbol with the name of the association being cached
      #
      # == Options
      #
      # * embed: Only true is supported, which is also the default, so
      #   IdentityCache will keep the values for this association in the same
      #   cache entry as the parent, instead of its own.
      # * inverse_name: The name of the parent in the association ( only
      #   necessary if the name is not the lowercase pluralization of the
      #   parent object's class)
      def cache_has_one(association, embed: true, inverse_name: nil)
        ensure_base_model
        check_association_for_caching(association)
        reflection = reflect_on_association(association)
        association_class = case embed
        when :id
          Cached::Reference::HasOne
        when true
          Cached::Recursive::HasOne
        else
          raise NotImplementedError
        end

        cached_has_ones[association] = association_class.new(
          association,
          reflection: reflection,
          inverse_name: inverse_name,
        ).tap(&:build)
      end

      # Will cache a single attribute on its own blob, it will add a
      # fetch_attribute_by_id (or the value of the by option).
      #
      # == Example:
      #   class Product
      #     include IdentityCache
      #     cache_attribute :quantity, by: :name
      #     cache_attribute :quantity, by: [:name, :vendor]
      #   end
      #
      # == Parameters
      # +attribute+ Symbol with the name of the attribute being cached
      #
      # == Options
      #
      # * by: Other attribute or attributes in the model to keep values indexed. Default is :id
      # * unique: if the index would only have unique values. Default is true
      def cache_attribute(attribute, by: :id, unique: true)
        cache_attribute_by_alias(attribute.inspect, attribute, by: by, unique: unique)
      end

      private

      def cache_attribute_by_alias(attribute, alias_name, by:, unique:)
        ensure_base_model
        alias_name = alias_name.to_sym
        unique = !!unique
        fields = Array(by)

        cache_indexes.push([alias_name, fields, unique])

        field_list = fields.join("_and_")
        arg_list = (0...fields.size).collect { |i| "arg#{i}" }.join(',')

        instance_eval(<<-CODE, __FILE__, __LINE__ + 1)
          def fetch_#{alias_name}_by_#{field_list}(#{arg_list})
            attribute_dynamic_fetcher(#{attribute}, #{fields.inspect}, [#{arg_list}], #{unique})
          end
        CODE

        if fields.length == 1
          instance_eval(<<-CODE, __FILE__, __LINE__ + 1)
            def fetch_multi_#{alias_name}_by_#{field_list}(index_values)
              batch_attribute_dynamic_fetcher(#{attribute}, #{fields.first.to_s.inspect}.freeze, index_values, #{unique})
            end
          CODE
        end
      end

      def attribute_dynamic_fetcher(attribute, fields, values, unique_index) #:nodoc:
        raise_if_scoped

        fields.each_with_index do |field, i|
          values[i] = type_for_attribute(field.to_s).cast(values[i])
        end

        if should_use_cache?
          cache_key = rails_cache_key_for_attribute_and_fields_and_values(attribute, fields, values, unique_index)
          IdentityCache.fetch(cache_key) do
            dynamic_attribute_cache_miss(attribute, fields, values, unique_index)
          end
        else
          dynamic_attribute_cache_miss(attribute, fields, values, unique_index)
        end
      end

      def dynamic_attribute_cache_miss(attribute, fields, values, unique_index)
        query = reorder(nil).where(Hash[fields.zip(values)])
        query = query.limit(1) if unique_index
        results = query.pluck(attribute)
        unique_index ? results.first : results
      end

      def batch_attribute_dynamic_fetcher(attribute, field, index_values, unique_index)
        raise_if_scoped

        type = type_for_attribute(field)
        index_values = index_values.map { |value| type.cast(value) }

        unless should_use_cache?
          return batch_dynamic_attribute_cache_miss(attribute, field, index_values, unique_index)
        end

        fields = [field]
        index_by_cache_key = index_values.each_with_object({}) do |index_value, index_hash|
          cache_key = rails_cache_key_for_attribute_and_fields_and_values(
            attribute, fields, [index_value], unique_index
          )
          index_hash[cache_key] = index_value
        end
        attribute_by_cache_key = IdentityCache.fetch_multi(index_by_cache_key.keys) do |unresolved_keys|
          unresolved_index_values = unresolved_keys.map { |cache_key| index_by_cache_key.fetch(cache_key) }
          resolved_attributes = batch_dynamic_attribute_cache_miss(
            attribute, field, unresolved_index_values, unique_index
          )
          unresolved_index_values.map { |index_value| resolved_attributes.fetch(index_value) }
        end
        result = {}
        attribute_by_cache_key.each do |cache_key, attribute_value|
          result[index_by_cache_key.fetch(cache_key)] = attribute_value
        end
        result
      end

      def batch_dynamic_attribute_cache_miss(attribute, index_field, values, unique_index)
        rows = reorder(nil).where(index_field => values).pluck(index_field, attribute)
        result = {}
        default = unique_index ? nil : []
        values.each do |index_value|
          result[index_value] = default.try!(:dup)
        end
        if unique_index
          rows.each do |index_value, attribute_value|
            result[index_value] = attribute_value
          end
        else
          rows.each do |index_value, attribute_value|
            result[index_value] << attribute_value
          end
        end
        result
      end

      def ensure_base_model
        if self != cached_model
          raise DerivedModelError, <<~MSG.squish
            IdentityCache class methods must be called on the same
            model that includes IdentityCache
          MSG
        end
      end

      def check_association_for_caching(association)
        unless (association_reflection = reflect_on_association(association))
          raise AssociationError, "Association named '#{association}' was not found on #{self.class}"
        end
        if association_reflection.options[:through]
          raise UnsupportedAssociationError, "caching through associations isn't supported"
        end
      end
    end
  end
end
