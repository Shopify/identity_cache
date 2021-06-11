# frozen_string_literal: true
module IdentityCache
  module Internal
    module EmbeddedFetching
      private

      def fetch_embedded(records)
        fetch_embedded_async(LoadStrategy::Eager, records) {}
      end

      def fetch_embedded_async(load_strategy, records)
        return yield if embedded_fetched?(records)

        klass = reflection.active_record
        cached_associations = klass.send(:embedded_associations)

        return yield if cached_associations.empty?

        return yield unless klass.primary_cache_index_enabled

        load_strategy.load_multi(klass.cached_primary_index, records.map(&:id)) do |cached_records_by_id|
          cached_associations.each_value do |cached_association|
            records.each do |record|
              next unless (cached_record = cached_records_by_id[record.id])
              cached_value = cached_association.read(cached_record)
              cached_association.write(record, cached_value)
            end
          end

          yield
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
