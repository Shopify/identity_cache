# frozen_string_literal: true
require "test_helper"

class ExpireByKeyValuesTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    AssociatedRecord.cache_attribute(:name)
    AssociatedRecord.cache_attribute(:name, by: :item_id)
    AssociatedRecord.cache_attribute(:name, by: [:id, :item_id])

    parent = Item.create!(title: "bob")
    parent.associated_records.create!(name: "foo")
    IdentityCache.cache.clear
  end

  def test_expire_by_key_values
    assert_queries(3) do
      assert_equal("foo", AssociatedRecord.fetch_name_by_id(1))
      assert_equal("foo", AssociatedRecord.fetch_name_by_item_id(1))
      assert_equal("foo", AssociatedRecord.fetch_name_by_id_and_item_id(1, 1))
    end

    assert_queries(0) do
      assert_equal("foo", AssociatedRecord.fetch_name_by_id(1))
      assert_equal("foo", AssociatedRecord.fetch_name_by_item_id(1))
      assert_equal("foo", AssociatedRecord.fetch_name_by_id_and_item_id(1, 1))
    end

    key_values = {
      id: 1,
      item_id: 1,
    }

    AssociatedRecord.cache_indexes.each do |index|
      index.expire_by_key_value(key_values)
    end

    assert_queries(3) do
      assert_equal("foo", AssociatedRecord.fetch_name_by_id(1))
      assert_equal("foo", AssociatedRecord.fetch_name_by_item_id(1))
      assert_equal("foo", AssociatedRecord.fetch_name_by_id_and_item_id(1, 1))
    end
  end

  def test_expire_by_key_values_raises_exception_on_missing_key
    by_id_index, by_item_id_index, by_multi_index = AssociatedRecord.cache_indexes
    missing_id_error_message =
      "AssociatedRecord attribute name expire_by_key_value - required fields: id. missing: id"
    missing_item_id_error_message =
      "AssociatedRecord attribute name expire_by_key_value - required fields: item_id. missing: item_id"
    missing_id_key_in_multi_error_message =
      "AssociatedRecord attribute name expire_by_key_value - required fields: id, item_id. missing: id"

    missing_id_error = assert_raises(IdentityCache::MissingKeyName) do
      by_id_index.expire_by_key_value({ item_id: 1 })
    end
    missing_item_id_error = assert_raises(IdentityCache::MissingKeyName) do
      by_item_id_index.expire_by_key_value({ id: 1 })
    end
    missing_id_in_multi_error = assert_raises(IdentityCache::MissingKeyName) do
      by_multi_index.expire_by_key_value({ item_id: 1 })
    end

    assert_equal(missing_id_error_message, missing_id_error.message)
    assert_equal(missing_item_id_error_message, missing_item_id_error.message)
    assert_equal(missing_id_key_in_multi_error_message, missing_id_in_multi_error.message)
  end
end
