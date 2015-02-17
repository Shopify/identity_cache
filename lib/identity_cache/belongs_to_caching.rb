module IdentityCache
  module BelongsToCaching
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute :cached_belongs_tos
      base.cached_belongs_tos = {}
    end

    module ClassMethods
      def cache_belongs_to(association, options = {})
        raise NotImplementedError if options[:embed]

        unless association_reflection = reflect_on_association(association)
          raise AssociationError, "Association named '#{association}' was not found on #{self.class}"
        end

        options = {}
        self.cached_belongs_tos[association] = options

        options[:embed]                   = false
        options[:cached_accessor_name]    = "fetch_#{association}"
        options[:foreign_key]             = association_reflection.foreign_key
        options[:association_class]       = association_reflection.klass
        options[:prepopulate_method_name] = "prepopulate_fetched_#{association}"

        build_normalized_belongs_to_cache(association, options)
      end

      def build_normalized_belongs_to_cache(association, options)
        self.class_eval(<<-CODE, __FILE__, __LINE__ + 1)
          def #{options[:cached_accessor_name]}
            if IdentityCache.should_use_cache? && #{options[:foreign_key]}.present? && !association(:#{association}).loaded?
              self.#{association} = #{options[:association_class]}.fetch_by_id(#{options[:foreign_key]})
            else
              #{association}
            end
          end

          def #{options[:prepopulate_method_name]}(record)
            self.#{association} = record
          end
        CODE
      end
    end
  end
end
