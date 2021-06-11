# frozen_string_literal: true

module IdentityCache
  module Internal
    module Reference
      class HasMany < Association
        def initialize(name, reflection:)
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
              assoc = association(:#{name})
              if assoc.klass.should_use_cache? && !assoc.loaded? && assoc.target.blank?
                #{records_variable_name} ||= #{reflection.class_name}.fetch_multi(#{cached_ids_name})
              else
                #{name}.to_a
              end
            end
          RUBY

          ParentModelExpiration.add_parent_expiry_hook(self)
        end

        def read(record)
          record.public_send(cached_ids_name)
        end

        def write(record, ids)
          record.instance_variable_set(ids_variable_name, ids)
        end

        def clear(record)
          [ids_variable_name, records_variable_name].each do |ivar|
            if record.instance_variable_defined?(ivar)
              record.remove_instance_variable(ivar)
            end
          end
        end

        def fetch(records)
          fetch_async(LoadStrategy::Eager, records) { |child_records| child_records }
        end

        def fetch_async(load_strategy, records)
          fetch_embedded_async(load_strategy, records) do
            ids_to_parent_record = records.each_with_object({}) do |record, hash|
              child_ids = record.send(cached_ids_name)
              child_ids.each do |child_id|
                hash[child_id] = record
              end
            end

            load_strategy.load_multi(
              reflection.klass.cached_primary_index,
              ids_to_parent_record.keys
            ) do |child_records_by_id|
              parent_record_to_child_records = Hash.new { |h, k| h[k] = [] }

              child_records_by_id.each do |id, child_record|
                parent_record = ids_to_parent_record.fetch(id)
                parent_record_to_child_records[parent_record] << child_record
              end

              parent_record_to_child_records.each do |parent, children|
                parent.instance_variable_set(records_variable_name, children)
              end

              yield child_records_by_id.values.compact
            end
          end
        end

        private

        def embedded_fetched?(records)
          record = records.first
          super || record.instance_variable_defined?(ids_variable_name)
        end

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
