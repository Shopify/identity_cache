# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module Cached
    module Reference
      class BelongsToTest < IdentityCache::TestCase
        def setup
          super
          @reflection = reflect(AssociatedRecord, :item)
          @belongs_to = BelongsTo.new(:item, reflection: @reflection)
        end

        attr_reader :reflection, :belongs_to

        def test_is_cached_association
          assert_equal(Cached::Association, BelongsTo.superclass.superclass)
        end

        def test_build
          belongs_to.build
          record = AssociatedRecord.new

          assert_operator(record, :respond_to?, :fetch_item)
        end

        def test_clear
          record = AssociatedRecord.new
          record.instance_variable_set(:@cached_item, Item.new)

          belongs_to.clear(record)

          refute_operator(record, :instance_variable_defined?, :@cached_item)
        end

        def test_embedded
          refute_predicate(belongs_to, :embedded?)
        end

        def test_embedded_recursively
          refute_predicate(belongs_to, :embedded_recursively?)
        end

        def test_embedded_by_reference
          refute_predicate(belongs_to, :embedded_by_reference?)
        end
      end
    end
  end
end
