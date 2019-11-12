# frozen_string_literal: true
module IdentityCache
  module BelongsToCaching
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute(:cached_belongs_tos)
      base.cached_belongs_tos = {}
    end

    module ClassMethods
      def cache_belongs_to(association)
        ensure_base_model

        unless reflection = reflect_on_association(association)
          raise AssociationError, "Association named '#{association}' was not found on #{self.class}"
        end

        if reflection.scope
          raise UnsupportedAssociationError, "caching association #{self}.#{association} is scoped which isn't supported"
        end

        cached_belongs_to = Cached::Reference::BelongsTo.new(
          association,
          reflection: reflection,
        )

        self.cached_belongs_tos[association] = cached_belongs_to.tap(&:build)
      end
    end
  end
end
