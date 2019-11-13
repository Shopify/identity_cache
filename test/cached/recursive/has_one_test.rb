# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module Cached
    module Recursive
      class HasOneTest < IdentityCache::TestCase
        def setup
          super
          @reflection = reflect(AssociatedRecord, :deeply_associated)
          @has_one = HasMany.new(
            :deeply_associated,
            inverse_name: :associated_record,
            reflection: @reflection
          )
        end

        attr_reader :reflection, :has_one

        def test_is_cached_association
          assert_equal(Cached::Association, HasOne.superclass.superclass)
        end

        def test_build
          has_one.build
          record = AssociatedRecord.new

          assert_operator(record, :respond_to?, :fetch_deeply_associated)
        end

        def test_clear
          record = AssociatedRecord.new
          record.instance_variable_set(:@cached_deeply_associated, DeeplyAssociatedRecord.new)

          has_one.clear(record)

          refute_operator(record, :instance_variable_defined?, :@cached_deeply_associated)
        end

        def test_embedded
          assert_predicate(has_one, :embedded?)
        end

        def test_embedded_recursively
          assert_predicate(has_one, :embedded_recursively?)
        end

        def test_embedded_by_reference
          refute_predicate(has_one, :embedded_by_reference?)
        end
      end
    end
  end
end
