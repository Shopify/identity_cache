# frozen_string_literal: true

require "test_helper"

class ParentModelExpirationTest < IdentityCache::TestCase
  def test_recursively_expire_parent_caches
    define_cache_indexes = lambda do
      AssociatedRecord.cache_has_many(:deeply_associated_records, embed: true)
      Item.cache_has_many(:associated_records, embed: true)
    end
    define_cache_indexes.call

    # setup fixtures
    item = Item.new(title: "grandparent")

    associated_record = AssociatedRecord.new(name: "parent")
    item.associated_records << associated_record

    deeply_associated_record = DeeplyAssociatedRecord.new(name: "child")
    associated_record.deeply_associated_records << deeply_associated_record

    item.save!

    Item.fetch(item.id) # fill cache

    # reset models to test lazy parent expiration hooks
    teardown_models
    setup_models
    define_cache_indexes.call

    DeeplyAssociatedRecord.find(deeply_associated_record.id).update(name: "updated child")

    fetched_name = Item.fetch(item.id).fetch_associated_records.first.fetch_deeply_associated_records.first.name
    assert_equal("updated child", fetched_name)
  end

  def test_custom_parent_foreign_key_expiry
    define_cache_indexes = lambda do
      CustomParentRecord.cache_has_many(:custom_child_records, embed: true)
      CustomChildRecord.cache_belongs_to(:custom_parent_record)
    end
    define_cache_indexes.call
    old_parent = CustomParentRecord.new(parent_primary_key: 1)
    old_parent.save!
    child = CustomChildRecord.new(child_primary_key: 10, parent_id: old_parent.id)
    child.save!

    # Warm the custom_child_records embedded cache on the old parent record
    assert_equal(10, CustomParentRecord.fetch(1).fetch_custom_child_records.first.child_primary_key)

    new_parent = CustomParentRecord.new(parent_primary_key: 2)
    new_parent.save!
    # Warm the custom_child_records embedded cache on the new parent record
    assert_empty(CustomParentRecord.fetch(2).fetch_custom_child_records)

    # Now invoke a db update, where the child switches parent
    child.parent_id = new_parent.parent_primary_key
    child.save!

    # the old parent's custom_child_records embedded cache should be invalidated and empty
    assert_empty(CustomParentRecord.fetch(1).fetch_custom_child_records)
    # the new parent's custom_child_records embedded cache should be invalidated and filled with the new association
    assert_equal(10, CustomParentRecord.fetch(2).fetch_custom_child_records.first.child_primary_key)
  end
end
