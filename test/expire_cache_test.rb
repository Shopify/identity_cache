# frozen_string_literal: true

require "test_helper"

class ExpireCacheTest < IdentityCache::TestCase
  def setup
    super

    Item.cache_index(:title, unique: true)
    Item.cache_index(:id, :title, unique: true)

    @record = Item.new
    @record.id = 1
    @record.title = "bob"

    Spy.on(Item.cached_primary_index, :load_one_from_db).and_return do
      @record
    end
  end

  def test_expire_cache_hit
    assert_equal(@record, Item.fetch(1))
    refute_equal(IdentityCache::DELETED, backend.read(@record.primary_cache_index_key))
    assert(@record.expire_cache)
    assert_equal(IdentityCache::DELETED, backend.read(@record.primary_cache_index_key))
  end

  def test_expire_cache_on_failure
    assert_equal(@record, Item.fetch(1))
    refute_equal(IdentityCache::DELETED, backend.read(@record.primary_cache_index_key))

    Spy.on(backend, :write_entry).and_return { false }

    refute(@record.expire_cache)
    refute_equal(IdentityCache::DELETED, backend.read(@record.primary_cache_index_key))
  end
end
