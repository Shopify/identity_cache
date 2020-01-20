# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module LoadStrategy
    class LazyTest < IdentityCache::TestCase
      def setup
        super
        @lazy = Lazy.new
      end

      attr_reader :lazy

      def test_load
        record = AssociatedRecord.create!
        lazy.load(AssociatedRecord.cached_primary_index, record.id) do |loaded_record|
          assert_equal record, loaded_record
        end

        lazy.load_now
      end

      def test_load_multi
        records = create_list(:associated_record, 3)
        records_by_id = records.map { |record| [record.id, record] }.to_h
        lazy.load_multi(AssociatedRecord.cached_primary_index, records.map(&:id)) do |loaded_records_by_id|
          assert_equal records_by_id, loaded_records_by_id
        end

        lazy.load_now
      end

      def test_load_batch
        associated_record_ids = create_list(:associated_record, 3).map(&:id)
        deeply_associated_record_ids = create_list(:deeply_associated_record, 3).map(&:id)
        item_record_ids = create_list(:item, 3).map(&:id)
        ids_by_cache_fetcher = {
          AssociatedRecord.cached_primary_index => associated_record_ids,
          DeeplyAssociatedRecord.cached_primary_index => deeply_associated_record_ids,
          Item.cached_primary_index => item_record_ids,
        }
        lazy.load_batch(ids_by_cache_fetcher) do |loaded_records_by_id_by_cache_fetcher|
          ids_by_cache_fetcher.each do |cache_fetcher, ids|
            loaded_records_by_id = loaded_records_by_id_by_cache_fetcher.fetch(cache_fetcher)
            assert_equal ids, loaded_records_by_id.keys.sort
            assert_equal ids, loaded_records_by_id.values.map(&:id).sort
          end
        end

        lazy.load_now
      end

      def test_lazy_load
        lazy.lazy_load do |yielded_lazy_loader|
          assert_same lazy, yielded_lazy_loader
        end
      end

      def test_load_now
        callee = mock(called: true)
        record = AssociatedRecord.create!

        lazy.load(AssociatedRecord.cached_primary_index, record.id) do
          callee.called
        end

        lazy.load_now
      end
    end
  end
end
