module IdentityCache
  module BelongsToCaching
    extend ActiveSupport::Concern

    included do |base|
      base.class_attribute :cached_belongs_tos
      base.cached_belongs_tos = {}
    end

    module ClassMethods
      def cache_belongs_to(association, options = {})
        self.cached_belongs_tos[association] = options

        options[:embed] ||= false
        options[:cached_accessor_name]    ||= "fetch_#{association}"
        options[:foreign_key]             ||= reflect_on_association(association).foreign_key
        options[:association_class]       ||= reflect_on_association(association).klass
        options[:prepopulate_method_name] ||= "prepopulate_fetched_#{association}"

        build_embedded_belongs_to_cache(association, options) if options[:embed]

        build_normalized_belongs_to_cache(association, options)
      end

      def build_embedded_belongs_to_cache(association, options)
        self.class_eval <<-CODE, __FILE__, __LINE__ + 1
          def #{association}
            if IdentityCache.should_cache? && #{options[:foreign_key]}.present? && !association(:#{association}).loaded?
              self.#{association} = #{options[:association_class]}.fetch_by_id(#{options[:foreign_key]})
            else
              super
            end
          end
        CODE
      end

      def build_normalized_belongs_to_cache(association, options)
        self.class_eval <<-CODE, __FILE__, __LINE__ + 1
          def #{options[:cached_accessor_name]}
            if IdentityCache.should_cache? && #{options[:foreign_key]}.present? && !association(:#{association}).loaded?
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
