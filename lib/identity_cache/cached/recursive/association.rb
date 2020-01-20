# frozen_string_literal: true
module IdentityCache
  module Cached
    module Recursive
      class Association < Cached::Association # :nodoc:
        def initialize(name, inverse_name:, reflection:)
          super
          @dehydrated_variable_name = :"@dehydrated_#{name}"
        end

        attr_reader :dehydrated_variable_name

        def build
          reflection.active_record.class_eval(<<-RUBY, __FILE__, __LINE__ + 1)
            def #{cached_accessor_name}
              fetch_recursively_cached_association(
                :#{records_variable_name},
                :#{dehydrated_variable_name},
                :#{name}
              )
            end
          RUBY

          ParentModelExpiration.add_parent_expiry_hook(self)
        end

        def read(record)
          record.public_send(cached_accessor_name)
        end

        def write(record, records)
          record.instance_variable_set(records_variable_name, records)
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

        def embedded_fetched?(records)
          record = records.first
          super || record.instance_variable_defined?(dehydrated_variable_name)
        end
      end
    end
  end
end
