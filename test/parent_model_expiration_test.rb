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

  def test_check_for_unsupported_parent_expiration_entries
    Item.cache_has_many(:associated_records, embed: true)

    Item.send(:check_for_unsupported_parent_expiration_entries)
    exc = assert_raises do
      AssociatedRecord.send(:check_for_unsupported_parent_expiration_entries)
    end
    assert_equal(
      "Unsupported manual expiration of AssociatedRecord record that is embedded in parent associations:\n- item",
      exc.message
    )
  end
end
