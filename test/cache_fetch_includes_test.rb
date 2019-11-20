# frozen_string_literal: true
require "test_helper"

class CacheFetchIncludesTest < IdentityCache::TestCase
  def setup
    super
  end

  def test_cached_embedded_has_manys_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, embed: true)
    assert_equal([:associated_records], cache_fetch_includes(Item))
  end

  def test_cached_nonembedded_has_manys_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, embed: :ids)
    assert_equal([], cache_fetch_includes(Item))
  end

  def test_cached_has_ones_are_included_in_includes
    Item.send(:cache_has_one, :associated)
    assert_equal([:associated], cache_fetch_includes(Item))
  end

  def test_cached_nonembedded_belongs_tos_are_not_included_in_includes
    Item.send(:cache_belongs_to, :item)
    assert_equal([], cache_fetch_includes(Item))
  end

  def test_cached_child_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, embed: true)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: true)
    assert_equal([{ associated_records: [:deeply_associated_records] }], cache_fetch_includes(Item))
  end

  def test_multiple_cached_associations_and_child_associations_are_included_in_includes
    Item.send(:cache_has_many, :associated_records, embed: true)
    PolymorphicRecord.send(:include, IdentityCache::WithoutPrimaryIndex)
    Item.send(:cache_has_many, :polymorphic_records, { inverse_name: :owner, embed: true })
    Item.send(:cache_has_one, :associated, embed: true)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: true)
    assert_equal([
      { associated_records: [:deeply_associated_records] },
      :polymorphic_records,
      { associated: [:deeply_associated_records] }
    ],  cache_fetch_includes(Item))
  end

  private

  def cache_fetch_includes(model)
    model.cached_record_fetcher.send(:db_load_includes)
  end
end
