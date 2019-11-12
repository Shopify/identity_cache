# frozen_string_literal: true
require "test_helper"

class LazyLoadAssociatedClassesTest < IdentityCache::TestCase
  def test_cache_has_many_does_not_load_associated_class
    Item.has_many(:missing_model)
    Item.cache_has_many(:missing_model)
  end

  def test_cache_has_many_embed_does_not_load_associated_class
    Item.has_many(:missing_model)
    Item.cache_has_many(:missing_model, embed: true)
  end

  def test_cache_has_one_does_not_load_associated_class
    Item.has_one(:missing_model)
    Item.cache_has_one(:missing_model)
  end

  def test_cache_invalidation
    Item.cache_has_many(:associated_records, embed: true)
    associated_record = AssociatedRecord.new(name: 'baz')
    item = Item.new(title: 'foo')
    item.associated_records << associated_record
    item.save!
    Item.fetch(item.id)

    assert_queries(0) do
      assert_equal 'baz', Item.fetch(item.id).fetch_associated_records.first.name
    end
    associated_record.update_attributes!(name: 'buzz')
    assert_queries(2) do
      assert_equal 'buzz', Item.fetch(item.id).fetch_associated_records.first.name
    end
  end

  def test_avoid_caching_embed_association_missing_include_identity_cache
    Item.cache_has_many(:not_cached_records, embed: true)

    assert_memcache_operations(0) do
      err1 = assert_raises(IdentityCache::UnsupportedAssociationError) do
        Item.fetch(1)
      end
      assert_equal 'cached association Item#not_cached_records requires associated class NotCachedRecord to include IdentityCache or IdentityCache::WithoutPrimaryIndex', err1.message
      err2 = assert_raises(IdentityCache::UnsupportedAssociationError) do
        Item.fetch_multi([1])
      end
      assert_equal err1.message, err2.message
    end
  end

  def test_avoid_caching_id_embed_association_missing_include_identity_cache
    Item.cache_has_many(:not_cached_records, embed: :ids)

    assert_memcache_operations(0) do
      err1 = assert_raises(IdentityCache::UnsupportedAssociationError) do
        Item.fetch(1)
      end
      assert_equal 'cached association Item#not_cached_records requires associated class NotCachedRecord to include IdentityCache', err1.message
      err2 = assert_raises(IdentityCache::UnsupportedAssociationError) do
        Item.fetch_multi([1])
      end
      assert_equal err1.message, err2.message
    end
  end
end

