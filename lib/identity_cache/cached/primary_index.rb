# frozen_string_literal: true

module IdentityCache
  module Cached
    class PrimaryIndex
      attr_reader :model

      def initialize(model)
        @model = model
      end

      def fetch(id, cache_fetcher_options)
        id = cast_id(id)
        return unless id

        record = if model.should_use_cache?
          object = CacheKeyLoader.load(self, id, cache_fetcher_options)
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
        id_to_record_hash = if model.should_use_cache?
          id_to_record_hash = CacheKeyLoader.load_multi(self, ids)
        else
          load_multi_from_db(ids)
        end
        records = ids.map { |id| id_to_record_hash[id] }
        records.compact!
        records
      end

      def expire(id)
        id = cast_id(id)
        if Thread.current[:idc_deferred_expiration]
          Thread.current[:idc_child_records_to_expire] << cache_key(id)
        else
          IdentityCache.cache.delete(cache_key(id))
        end
      end

      def cache_key(id)
        "#{model.rails_cache_key_namespace}#{cache_key_prefix}#{id}"
      end

      def load_one_from_db(id)
        record = build_query(id).take
        if record
          model.send(:setup_embedded_associations_on_miss, [record])
          record.send(:mark_as_loaded_by_idc)
        end
        record
      end

      def load_multi_from_db(ids)
        return {} if ids.empty?

        records = build_query(ids).to_a
        model.send(:setup_embedded_associations_on_miss, records)
        records.each { |record| record.send(:mark_as_loaded_by_idc) }
        records.index_by(&:id)
      end

      def cache_encode(record)
        Encoder.encode(record)
      end

      def cache_decode(cache_value)
        Encoder.decode(cache_value, model)
      end

      private

      def cast_id(id)
        model.type_for_attribute(model.primary_key).cast(id)
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
