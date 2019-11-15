# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module Prefetch
    class SegmentTest < IdentityCache::TestCase
      def setup
        super

        AssociatedRecord.send(:cache_belongs_to, :item)

        @record = AssociatedRecord.create!
        @cached_association = AssociatedRecord.cached_association(:item)
        @operation = Operation.new(AssociatedRecord, [], AssociatedRecord.all)
        @batch = add_batch(operation, 0)
      end

      attr_reader :record, :cached_association, :operation, :batch

      def test_load
        segment = batch.add(cached_association, operation)

        cached_association.expects(:fetch).with([record])

        segment.load
      end

      def test_nested_load
        Item.send(:cache_has_many, :associated_records)

        next_batch = add_batch(operation, 1)
        nested_cached_association = Item.cached_association(:associated_records)
        nested_record = Item.create!(title: "Rocket Shoes")
        record.update!(item: nested_record)

        segment = batch.add(cached_association, operation)
        nested_segment = next_batch.add(nested_cached_association, segment)

        cached_association.expects(:fetch).with([record]).returns([nested_record])
        nested_cached_association.expects(:fetch).with([nested_record])


        nested_segment.load
      end

      def test_records
        nested_record = Item.create!(title: "Invisible Ink")
        record.update!(item: nested_record)

        cached_association.expects(:fetch).with([record]).returns([nested_record])

        segment = batch.add(cached_association, operation)

        assert_equal([nested_record], segment.records)
      end

      private

      def add_batch(operation, level)
        operation.batches[level] = Batch.new(operation)
      end
    end
  end
end
