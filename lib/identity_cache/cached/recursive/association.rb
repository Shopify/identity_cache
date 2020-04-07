# frozen_string_literal: true
module IdentityCache
  module Cached
    module Recursive
      class Association < Cached::Association # :nodoc:
        def initialize(name, reflection:)
          super
          @dehydrated_variable_name = :"@dehydrated_#{name}"
        end

        attr_reader :dehydrated_variable_name

        def build
          cached_association = self

          model = reflection.active_record
          model.send(:define_method, cached_accessor_name) do
            cached_association.read(self)
          end

          ParentModelExpiration.add_parent_expiry_hook(self)
        end

        def read(record)
          assoc = record.association(name)

          if assoc.klass.should_use_cache? && !assoc.loaded? && assoc.target.blank?
            if record.instance_variable_defined?(records_variable_name)
              record.instance_variable_get(records_variable_name)
            elsif record.instance_variable_defined?(dehydrated_variable_name)
              dehydrated_target = record.instance_variable_get(dehydrated_variable_name)
              association_target = hydrate_association_target(assoc.klass, dehydrated_target)
              record.remove_instance_variable(dehydrated_variable_name)
              set_with_inverse(record, association_target)
            else
              assoc.load_target
            end
          else
            assoc.load_target
          end
        end

        def write(record, association_target)
          record.instance_variable_set(records_variable_name, association_target)
        end

        def set_with_inverse(record, association_target)
          set_inverse(record, association_target)
          write(record, association_target)
        end

        def clear(record)
          if record.instance_variable_defined?(records_variable_name)
            record.remove_instance_variable(records_variable_name)
          end
        end

        def fetch(records)
          fetch_async(LoadStrategy::Eager, records) { |child_records| child_records }
        end

        def fetch_async(load_strategy, records)
          fetch_embedded_async(load_strategy, records) do
            yield records.flat_map(&cached_accessor_name).tap(&:compact!)
          end
        end

        def embedded_by_reference?
          false
        end

        def embedded_recursively?
          true
        end

        private

        def set_inverse(record, association_target)
          return if association_target.nil?
          associated_class = reflection.klass
          inverse_cached_association = associated_class.cached_belongs_tos[inverse_name]
          return unless inverse_cached_association

          if association_target.is_a?(Array)
            association_target.each do |child_record|
              inverse_cached_association.write(child_record, record)
            end
          else
            inverse_cached_association.write(association_target, record)
          end
        end

        def hydrate_association_target(associated_class, dehydrated_value)
          dehydrated_value = IdentityCache.unmap_cached_nil_for(dehydrated_value)
          if dehydrated_value.is_a?(Array)
            dehydrated_value.map { |coder| Encoder.decode(coder, associated_class) }
          else
            Encoder.decode(dehydrated_value, associated_class)
          end
        end

        def embedded_fetched?(records)
          record = records.first
          super || record.instance_variable_defined?(dehydrated_variable_name)
        end
      end
    end
  end
end
