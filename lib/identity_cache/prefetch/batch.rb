module IdentityCache
  module Prefetch
    class Batch
      def initialize(operation)
        @operation = operation
        @segments   = []
      end

      attr_reader :segments

      def add(cached_association, parent)
        Segment.new(self, cached_association, parent).tap do |segment|
          segments << segment
        end
      end

      def load
        segments.map(&:load)
      end
    end
  end
end
