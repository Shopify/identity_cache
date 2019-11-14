# frozen_string_literal: true
module IdentityCache
  module Cached
    module EmbeddedFetching
      private

      def fetch_embedded(records)
        return if embedded_fetched?(records)

        klass = reflection.active_record
        cached_associations = klass.send(:embedded_associations)

        return if cached_associations.empty?

        return unless klass.primary_cache_index_enabled

        cached_records_by_id = klass.fetch_multi(records.map(&:id)).index_by(&:id)

        cached_associations.each_value do |cached_association|
          records.each do |record|
            next unless (cached_record = cached_records_by_id[record.id])
            cached_valiue = cached_association.read(cached_record)
            cached_association.write(record, cached_valiue)
          end
        end
      end

      def embedded_fetched?(records)
        # NOTE: Assume all records are the same, so just check the first one.
        record = records.first
        record.association(name).loaded? || record.instance_variable_defined?(records_variable_name)
      end
    end
  end
end
