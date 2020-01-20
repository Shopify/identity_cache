# frozen_string_literal: true
module IdentityCache
  module ConfigurationDSL
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute(:cache_indexes)
      base.class_attribute(:cached_has_manys)
      base.class_attribute(:cached_has_ones)

      base.cached_has_manys = {}
      base.cached_has_ones = {}
      base.cache_indexes = []
    end

    module ClassMethods
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
        cache_attribute_by_alias(attribute, alias_name: attribute, by: by, unique: unique)
      end

      private

      def cache_attribute_by_alias(attribute_or_proc, alias_name:, by:, unique:)
        ensure_base_model
        fields = Array(by)

        klass = fields.one? ? Cached::AttributeByOne : Cached::AttributeByMulti
        cached_attribute = klass.new(self, attribute_or_proc, alias_name, fields, unique)
        cached_attribute.build
        cache_indexes.push(cached_attribute)
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
