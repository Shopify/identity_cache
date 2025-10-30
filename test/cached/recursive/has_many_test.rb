# frozen_string_literal: true

require "test_helper"

module IdentityCache
  module Cached
    module Recursive
      class HasManyTest < IdentityCache::TestCase
        def setup
          super
          @reflection = reflect(AssociatedRecord, :deeply_associated_records)
          @has_many = HasMany.new(:deeply_associated_records, reflection: @reflection)
        end

        attr_reader :reflection, :has_many

        def test_is_cached_association
          assert_equal(Cached::Association, HasMany.superclass.superclass)
        end

        def test_build
          has_many.build
          record = AssociatedRecord.new

          assert_operator(record, :respond_to?, :fetch_deeply_associated_records)
        end

        def test_clear
          record = AssociatedRecord.new
          record.instance_variable_set(:@cached_deeply_associated_records, [])

          has_many.clear(record)

          refute_operator(record, :instance_variable_defined?, :@cached_deeply_associated_records)
        end

        def test_embedded
          assert_predicate(has_many, :embedded?)
        end

        def test_embedded_recursively
          assert_predicate(has_many, :embedded_recursively?)
        end

        def test_embedded_by_reference
          refute_predicate(has_many, :embedded_by_reference?)
        end

        def test_thread_safety_hydration
          # Simulate race condition by setting up a dehydrated record
          record = AssociatedRecord.new
          dehydrated_data = [{ "id" => 1, "name" => "Test" }] # Mock dehydrated data
          record.instance_variable_set(has_many.dehydrated_variable_name, dehydrated_data)

          # Simulate multiple threads trying to hydrate concurrently
          threads = []
          errors = []

          10.times do
            threads << Thread.new do
              begin
                # Call the cached accessor which triggers hydration
                record.fetch_deeply_associated_records
              rescue => e
                errors << e
              end
            end
          end

          threads.each(&:join)

          # Assert no NameError occurred (which would indicate the race condition)
          assert_empty(errors, "Race condition detected: #{errors.map(&:message).join(', ')}")
        end
      end
    end
  end
end
