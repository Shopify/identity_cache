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
        if options[:embed]
          raise NotImplementedError
        else
          build_normalized_belongs_to_cache(association, options)
        end
      end

      def build_normalized_belongs_to_cache(association, options)
        self.class_eval(ruby = <<-CODE, __FILE__, __LINE__)
          def #{options[:cached_accessor_name]}
            if IdentityCache.should_cache? && #{options[:foreign_key]}.present? && !association(:#{association}).loaded?
              self.#{association} = #{options[:association_class]}.fetch_by_id(#{options[:foreign_key]})
            else
              load_and_readonlyify(:#{association})
            end
          end

          def #{options[:prepopulate_method_name]}(record)
            self.#{association} = record
          end
        CODE
      end
    end

    def load_and_readonlyify(association_name)
      record_or_records = send(association_name)
      if self.class.reflect_on_association(association_name).collection?
        record_or_records.each do |child_record|
          child_record.readonly!
        end
      else
        record_or_records.try(:readonly!)
      end
      record_or_records
    end
  end
end
