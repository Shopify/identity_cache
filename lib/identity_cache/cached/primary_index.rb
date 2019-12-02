# frozen_string_literal: true

module IdentityCache
  module Cached
    class PrimaryIndex
      attr_reader :model

      def initialize(model)
        @model = model
      end

      def fetch(id)
        id = cast_id(id)
        return unless id
        record = if model.should_use_cache?
          object = nil
          cache_value = IdentityCache.fetch(cache_key(id)) do
            cache_encode(object = load_one_from_db(id))
          end
          object ||= cache_decode(cache_value)
          if object && object.id != id
            IdentityCache.logger.error(
              <<~MSG.squish
                [IDC id mismatch] fetch_by_id_requested=#{id}
                fetch_by_id_got=#{object.id}
                for #{object.inspect[(0..100)]}
              MSG
            )
          end
          object
        else
          load_one_from_db(id)
        end
        record
      end

      def fetch_multi(ids)
        ids.map! { |id| cast_id(id) }.compact!
        records = if model.should_use_cache?
          cache_keys = ids.map { |id| cache_key(id) }
          key_to_id_map = Hash[cache_keys.zip(ids)]
          key_to_record_map = {}

          coders_by_key = IdentityCache.fetch_multi(cache_keys) do |unresolved_keys|
            ids = unresolved_keys.map { |key| key_to_id_map[key] }
            records = load_multi_from_db(ids)
            key_to_record_map = records.compact.index_by { |record| cache_key(record.id) }
            records.map { |record| cache_encode(record) }
          end

          cache_keys.map do |key|
            key_to_record_map[key] || cache_decode(coders_by_key[key])
          end
        else
          load_multi_from_db(ids)
        end
        records.compact!
        records
      end

      def expire(id)
        id = cast_id(id)
        IdentityCache.cache.delete(cache_key(id))
      end

      def cache_key(id)
        "#{model.rails_cache_key_namespace}#{cache_key_prefix}#{id}"
      end

      private

      def cast_id(id)
        model.type_for_attribute(model.primary_key).cast(id)
      end

      def load_one_from_db(id)
        record = build_query(id).take
        model.send(:setup_embedded_associations_on_miss, [record]) if record
        record
      end

      def load_multi_from_db(ids)
        return [] if ids.empty?

        ids = ids.map { |id| model.connection.type_cast(id, id_column) }
        records = build_query(ids).to_a
        model.send(:setup_embedded_associations_on_miss, records)
        records_by_id = records.index_by(&:id)
        ids.map { |id| records_by_id[id] }
      end

      def cache_encode(record)
        Encoder.encode(record)
      end

      def cache_decode(cache_value)
        Encoder.decode(cache_value, model)
      end

      def id_column
        @id_column ||= model.columns.detect { |c| c.name == model.primary_key }
      end

      def build_query(id_or_ids)
        model.where(model.primary_key => id_or_ids).includes(model.send(:cache_fetch_includes))
      end

      def cache_key_prefix
        @cache_key_prefix ||= "blob:#{model.base_class.name}:" \
          "#{IdentityCache::CacheKeyGeneration.denormalized_schema_hash(model)}:"
      end
    end
  end
end
