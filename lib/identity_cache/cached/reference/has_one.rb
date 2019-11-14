# frozen_string_literal: true
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
          RUBY

          ParentModelExpiration.add_parent_expiry_hook(self)
        end

        def read(record)
          record.public_send(cached_id_name)
        end

        def write(record, id)
          record.instance_variable_set(id_variable_name, id)
        end

        def clear(record)
          [id_variable_name, records_variable_name].each do |ivar|
            if record.instance_variable_defined?(ivar)
              record.remove_instance_variable(ivar)
            end
          end
        end

        def fetch(records)
          fetch_embedded(records)

          ids_to_parent_record = records.each_with_object({}) do |record, hash|
            child_id = record.send(cached_id_name)
            hash[child_id] = record if child_id
          end

          parent_record_to_child_record = {}

          child_records = reflection.klass.fetch_multi(*ids_to_parent_record.keys)
          child_records.each do |child_record|
            parent_record = ids_to_parent_record[child_record.id]
            parent_record_to_child_record[parent_record] ||= child_record
          end

          parent_record_to_child_record.each do |parent, child|
            parent.instance_variable_set(records_variable_name, child)
          end

          child_records
        end

        private

        def embedded_fetched?(records)
          record = records.first
          super || record.instance_variable_defined?(id_variable_name)
        end

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
