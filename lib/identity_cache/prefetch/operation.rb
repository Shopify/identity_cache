module IdentityCache
  module Prefetch
    class Operation
      def initialize(klass, associations, records)
        @records = records.to_a
        @batches = {}

        build(klass, associations)
      end

      attr_reader :batches, :records

      def load
        batches.each_value(&:load)
      end

      private

      def build(klass, associations, parent: self, level: 0)
        return if records.empty?

        batch = batches[level] ||= Batch.new(self)

        Array.wrap(associations).each do |association|
          case association
          when Symbol
            batch.add(
              klass.cached_association(association),
              parent
            )
          when Hash
            association.each do |parent_association, nested_associations|
              segment = batch.add(
                klass.cached_association(parent_association),
                parent
              )

              nested_klass = klass.reflect_on_association(parent_association).klass

              build(
                nested_klass,
                nested_associations,
                parent: segment,
                level: level.next
              )
            end
          else
            raise TypeError, "Invalid association class #{association.class}"
          end
        end
      end
    end
  end
end
