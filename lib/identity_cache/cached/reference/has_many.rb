# frozen_string_literal: true
module IdentityCache
  module Cached
    module Reference
      class HasMany < Association # :nodoc:
        def initialize(name, inverse_name:, reflection:)
          super
          @cached_ids_name = "fetch_#{ids_name}"
          @ids_variable_name = :"@#{ids_cached_reader_name}"
        end

        attr_reader :cached_ids_name, :ids_variable_name

        def build
          reflection.active_record.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
            attr_reader :#{ids_cached_reader_name}

            def #{cached_ids_name}
              #{ids_variable_name} ||= #{ids_name}
            end

            def #{cached_accessor_name}
              association_klass = association(:#{name}).klass
              if association_klass.should_use_cache? && !#{name}.loaded?
                #{records_variable_name} ||= #{reflection.class_name}.fetch_multi(#{cached_ids_name})
              else
                #{name}.to_a
              end
            end
          RUBY

          ParentModelExpiration.add_parent_expiry_hook(self)
        end

        def clear(record)
          [ids_variable_name, records_variable_name].each do |ivar|
            if record.instance_variable_defined?(ivar)
              record.remove_instance_variable(ivar)
            end
          end
        end

        private

        def singular_name
          name.to_s.singularize
        end

        def ids_name
          "#{singular_name}_ids"
        end

        def ids_cached_reader_name
          "cached_#{ids_name}"
        end
      end
    end
  end
end
