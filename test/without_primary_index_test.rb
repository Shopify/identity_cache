# frozen_string_literal: true
require "test_helper"

module IdentityCache
  class WithoutPrimaryIndexTest < IdentityCache::TestCase
    def setup
      super
      AssociatedRecord.cache_attribute(:name)

      @parent = Item.create!(title: "bob")
      @record = @parent.associated_records.create!(name: "foo")
    end

    def test_cache_indexed_columns_returns_the_correct_columns_for_expiration
      AssociatedRecord.cache_attribute(:name, by: :item_id)
      expected_result = [:id, :item_id]
      assert_equal(expected_result, AssociatedRecord.cache_indexed_columns)
    end

    def test_expire_cache_for_update
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

    def test_expire_cache_for_update_raises_when_a_hash_is_missing_an_index_key
      expected_error_message = "key not found: :id"
      old_values = {
        name: "foo",
      }
      new_values = {
        name: "bar",
      }

      error = assert_raises(KeyError) do
        AssociatedRecord.expire_cache_for_update(old_values, new_values)
      end

      assert_equal(expected_error_message, error.message)
    end

    def test_expire_cache_for_insert
      test_record_name = "Test Record"
      AssociatedRecord.insert_all([{name: test_record_name}])
      test_record = AssociatedRecord.find_by(name: test_record_name)
      expire_hash_keys = {
        id: test_record.id,
      }
      
      assert_equal(test_record_name, AssociatedRecord.fetch_name_by_id(test_record.id))
      AssociatedRecord.expire_cache_for_insert(expire_hash_keys)
      assert_queries(1) do
        assert_equal(test_record_name, AssociatedRecord.fetch_name_by_id(test_record.id))
      end
    end

    def test_expire_cache_for_delete
      assert_equal("foo", AssociatedRecord.fetch_name_by_id(@record.id))
      expire_hash_keys = {
        id: @record.id,
      }

      AssociatedRecord.delete(@record.id)
      assert_equal("foo", AssociatedRecord.fetch_name_by_id(@record.id))
      
      AssociatedRecord.expire_cache_for_delete(expire_hash_keys)
      assert_queries(1) do
        assert_nil(AssociatedRecord.fetch_name_by_id(@record.id))
      end
    end
  end
end