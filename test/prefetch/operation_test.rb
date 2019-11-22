# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module Prefetch
    class OperationTest < IdentityCache::TestCase
      def setup
        super

        AssociatedRecord.send(:cache_belongs_to, :item)
        AssociatedRecord.send(:cache_has_one, :deeply_associated, embed: :id)
        AssociatedRecord.send(:cache_has_many, :deeply_associated_records)
        DeeplyAssociatedRecord.send(:cache_belongs_to, :item)
        Item.send(:cache_has_one, :associated, embed: :id)

        @record = AssociatedRecord.create!
      end

      attr_reader :record

      def test_load
        operation = Operation.new(AssociatedRecord, :item, [record])

        operation.batches.each_value do |batch|
          batch.expects(:load)
        end

        operation.load
      end

      def test_records
        operation = Operation.new(AssociatedRecord, :item, AssociatedRecord.all)

        assert_equal([record], operation.records)
        assert_instance_of(Array, operation.records)
      end

      def test_batches
        operation = Operation.new(
          AssociatedRecord,
          [
            :item,
            { deeply_associated: :item },
            { deeply_associated_records: { item: :associated } },
          ],
          [record],
        )

        assert_equal(3, operation.batches.count)
        assert_equal(3, operation.batches.values.first.segments.count)
        assert_equal(2, operation.batches.values.second.segments.count)
        assert_equal(1, operation.batches.values.third.segments.count)
      end
    end
  end
end
