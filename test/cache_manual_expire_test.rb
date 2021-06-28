# frozen_string_literal: true
require "test_helper"

module IdentityCache
  class CacheManualExpireTest < IdentityCache::TestCase
    def setup
      super
      AssociatedRecord.cache_attribute(:name)

      @parent = Item.create!(title: "bob")
      @record = @parent.associated_records.create!(name: "foo")
      IdentityCache.cache.clear
    end

    def test_cache_indexed_columns_returns_the_correct_columns_for_expiration
      AssociatedRecord.cache_attribute(:name, by: :item_id)
      expected_result = [:id, :item_id]
      assert_equal(expected_result, AssociatedRecord.cache_indexed_columns)
    end

    def test_expire_cache_for_udate
      id = 1
      item_id = 1
      AssociatedRecord.cache_attribute(:item_id, by: :name)

      assert_queries(1) do
        assert_equal(item_id, AssociatedRecord.fetch_item_id_by_name("foo"))
      end

      AssociatedRecord.where(id: 1).update_all(name: "bar")
      old_values = {
        name: "foo",
        id: id,
      }
      new_values = {
        name: "bar",
        id: id,
      }

      AssociatedRecord.expire_cache_for_update(old_values, new_values)
      assert_queries(2) do
        assert_equal(item_id, AssociatedRecord.fetch_item_id_by_name("bar"))
        assert_nil(AssociatedRecord.fetch_item_id_by_name("foo"))
      end
    end

    def test_expire_cache_for_udate_raises_when_a_hash_is_missing_an_index_key
      expected_error_message = "key not found: :id"
      old_values = {
        name: "foo",
      }
      new_values = {
        name: "bar",
      }

      error = assert_raises do
        AssociatedRecord.expire_cache_for_update(old_values, new_values)
      end

      assert_equal(expected_error_message, error.message)
    end

    def test_expire_cache_for_insert
      id = 1
      AssociatedRecord.fetch_name_by_id(id)
      expire_hash_keys = {
        id: id,
      }

      AssociatedRecord.expire_cache_for_insert(expire_hash_keys)
      assert_queries(1) do
        assert_equal("foo", AssociatedRecord.fetch_name_by_id(id))
      end
    end

    def test_expire_cache_for_delete
      id = 1
      AssociatedRecord.fetch_name_by_id(1)
      expire_hash_keys = {
        id: id,
      }

      AssociatedRecord.expire_cache_for_delete(expire_hash_keys)
      assert_queries(1) do
        assert_equal("foo", AssociatedRecord.fetch_name_by_id(id))
      end
    end
  end
end
