# frozen_string_literal: true
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
          RUBY
        end

        def clear(record)
          if record.instance_variable_defined?(records_variable_name)
            record.remove_instance_variable(records_variable_name)
          end
        end

        def fetch(records)
          if reflection.polymorphic?
            types_to_parent_ids = {}

            records.each do |child_record|
              parent_id = child_record.send(reflection.foreign_key)
              next unless parent_id && !child_record.instance_variable_defined?(records_variable_name)
              parent_type = Object.const_get(child_record.send(reflection.foreign_type)).cached_model
              types_to_parent_ids[parent_type] = {} unless types_to_parent_ids[parent_type]
              types_to_parent_ids[parent_type][parent_id] = child_record
            end

            parent_records = []

            types_to_parent_ids.each do |type, ids_to_child_record|
              type_parent_records = type.fetch_multi(ids_to_child_record.keys)
              type_parent_records.each do |parent_record|
                child_record = ids_to_child_record[parent_record.id]
                child_record.instance_variable_set(records_variable_name, parent_record)
              end
              parent_records.append(type_parent_records)
            end
          else
            ids_to_child_record = records.each_with_object({}) do |child_record, hash|
              parent_id = child_record.send(reflection.foreign_key)
              if parent_id && !child_record.instance_variable_defined?(records_variable_name)
                hash[parent_id] = child_record
              end
            end
            parent_records = reflection.klass.fetch_multi(ids_to_child_record.keys)
            parent_records.each do |parent_record|
              child_record = ids_to_child_record[parent_record.id]
              child_record.instance_variable_set(records_variable_name, parent_record)
            end
          end

          parent_records
        end

        def embedded_by_reference?
          false
        end
      end
    end
  end
end
