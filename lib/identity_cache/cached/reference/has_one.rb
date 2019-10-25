module IdentityCache
  module Cached
    module Reference
      class HasOne < Association # :nodoc:
        def initialize(name, inverse_name:, reflection:)
          super
          @cached_id_name = "fetch_#{id_name}"
          @id_variable_name = :"@#{id_cached_reader_name}"
        end

        attr_reader :cached_id_name, :id_variable_name

        def build
          reflection.active_record.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
            attr_reader :#{id_cached_reader_name}

            def #{cached_id_name}
              return #{id_variable_name} if defined?(#{id_variable_name})
              #{id_variable_name} = association(:#{name}).scope.ids.first
            end

            def #{cached_accessor_name}
              association_klass = association(:#{name}).klass
              if association_klass.should_use_cache? && !association(:#{name}).loaded?
                #{records_variable_name} ||= #{reflection.class_name}.fetch(#{cached_id_name}) if #{cached_id_name}
              else
                #{name}
              end
            end

            def #{prepopulate_method_name}(record)
              #{records_variable_name} = record
            end
          RUBY

          ParentModelExpiration.add_parent_expiry_hook(self)
        end

        def clear(record)
          [id_variable_name, records_variable_name].each do |ivar|
            if record.instance_variable_defined?(ivar)
              record.remove_instance_variable(ivar)
            end
          end
        end

        private

        def id_name
          "#{name}_id"
        end

        def id_cached_reader_name
          "cached_#{id_name}"
        end
      end
    end
  end
end
