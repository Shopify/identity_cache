module IdentityCache
  module Cached
    module Reference
      class BelongsTo < Association # :nodoc:
        def initialize(name, reflection:)
          super(name, inverse_name: nil, reflection: reflection)
        end

        attr_reader :records_variable_name

        def build
          reflection.active_record.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
            def #{cached_accessor_name}
              association_klass = association(:#{name}).klass
              if association_klass.should_use_cache? && #{reflection.foreign_key}.present? && !association(:#{name}).loaded?
                if defined?(#{records_variable_name})
                  #{records_variable_name}
                else
                  #{records_variable_name} = association_klass.fetch_by_id(#{reflection.foreign_key})
                end
              else
                #{name}
              end
            end

            def #{prepopulate_method_name}(record)
              #{records_variable_name} = record
            end
          RUBY
        end

        def clear(record)
          if record.instance_variable_defined?(records_variable_name)
            record.remove_instance_variable(records_variable_name)
          end
        end

        def embedded_by_reference?
          false
        end
      end
    end
  end
end
