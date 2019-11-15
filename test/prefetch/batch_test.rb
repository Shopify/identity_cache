# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module Prefetch
    class BatchTest < IdentityCache::TestCase
      def setup
        super

        AssociatedRecord.send(:cache_belongs_to, :item)

        @record    = AssociatedRecord.create!
        @operation = Operation.new(AssociatedRecord, [], AssociatedRecord.all)
        @batch = add_batch(operation, 0)
      end

      attr_reader :record, :operation, :batch

      def test_load
        batch.segments.each do |segment|
          segment.expects(:load)
        end

        batch.load
      end

      def test_add
        batch.add(AssociatedRecord.cached_association(:item), operation)

        assert_equal(1, batch.segments.count)
      end

      private

      def add_batch(operation, level)
        operation.batches[level] = Batch.new(operation)
      end
    end
  end
end
