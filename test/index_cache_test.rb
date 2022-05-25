# frozen_string_literal: true

require "test_helper"

class IndexCacheTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  class WithoutSetup < IdentityCache::TestCase
    def test_no_queries_on_definition
      # should not do schema queries eagerly
      assert_no_queries(all: true) { Item.cache_index(:title, :id) }

      # make sure schema wasn't cached
      schema_queries = count_queries(all: true) { Item.primary_key }
      assert(schema_queries > 0)
    end
  end

  def setup
    super
    @record = Item.new
    @record.id = 1
    @record.title = "bob"
  end

  def test_fetch_with_garbage_input
    Item.cache_index(:title, :id)

    assert_queries(1) do
      assert_equal([], Item.fetch_by_title_and_id("garbage_title", "garbage_id"))
    end
  end

  def test_fetch_with_unique_adds_limit_clause
    Item.cache_index(:title, :id, unique: true)

    Item.connection.expects(:exec_query)
      .with(regexp_matches(/ LIMIT 1\Z/i), any_parameters)
      .returns(ActiveRecord::Result.new([], []))

    assert_nil(Item.fetch_by_title_and_id("title", "2"))
  end

  def test_unique_index_caches_nil
    Item.cache_index(:title, unique: true)
    assert_nil(Item.fetch_by_title("bob"))
    assert_equal(IdentityCache::CACHED_NIL, backend.read(cache_key(unique: true)))
  end

  def test_unique_index_expired_by_new_record
    Item.cache_index(:title, unique: true)
    IdentityCache.cache.write(cache_key(unique: true), IdentityCache::CACHED_NIL)
    @record.save!
    assert_equal(IdentityCache::DELETED, backend.read(cache_key(unique: true)))
  end

  def test_unique_index_filled_on_fetch_by
    Item.cache_index(:title, unique: true)
    @record.save!
    assert_equal(@record, Item.fetch_by_title("bob"))
    assert_equal(@record.id, backend.read(cache_key(unique: true)))
  end

  def test_unique_index_expired_by_updated_record
    Item.cache_index(:title, unique: true)
    @record.save!
    old_cache_key = cache_key(unique: true)
    IdentityCache.cache.write(old_cache_key, @record.id)

    @record.title = "robert"
    new_cache_key = cache_key(unique: true)
    IdentityCache.cache.write(new_cache_key, IdentityCache::CACHED_NIL)
    @record.save!
    assert_equal(IdentityCache::DELETED, backend.read(old_cache_key))
    assert_equal(IdentityCache::DELETED, backend.read(new_cache_key))
  end

  def test_non_unique_index_caches_empty_result
    Item.cache_index(:title)
    assert_equal([], Item.fetch_by_title("bob"))
    assert_equal([], backend.read(cache_key))
  end

  def test_non_unique_index_expired_by_new_record
    Item.cache_index(:title)
    IdentityCache.cache.write(cache_key, [])
    @record.save!
    assert_equal(IdentityCache::DELETED, backend.read(cache_key))
  end

  def test_non_unique_index_filled_on_fetch_by
    Item.cache_index(:title)
    @record.save!
    assert_equal([@record], Item.fetch_by_title("bob"))
    assert_equal([@record.id], backend.read(cache_key))
  end

  def test_non_unique_index_fetches_multiple_records
    Item.cache_index(:title)
    @record.save!
    record2 = Item.create(title: "bob") { |item| item.id = 2 }

    assert_equal([@record, record2], Item.fetch_by_title("bob"))
    assert_equal([1, 2], backend.read(cache_key))
  end

  def test_non_unique_index_expired_by_updating_record
    Item.cache_index(:title)
    @record.save!
    old_cache_key = cache_key
    IdentityCache.cache.write(old_cache_key, [@record.id])

    @record.title = "robert"
    new_cache_key = cache_key
    IdentityCache.cache.write(new_cache_key, [])
    @record.save!
    assert_equal(IdentityCache::DELETED, backend.read(old_cache_key))
    assert_equal(IdentityCache::DELETED, backend.read(new_cache_key))
  end

  def test_non_unique_index_expired_by_destroying_record
    Item.cache_index(:title)
    @record.save!
    IdentityCache.cache.write(cache_key, [@record.id])
    @record.destroy
    assert_equal(IdentityCache::DELETED, backend.read(cache_key))
  end

  def test_set_table_name_cache_fetch
    Item.cache_index(:title)
    Item.table_name = "items2"
    @record.save!
    assert_equal([@record], Item.fetch_by_title("bob"))
    assert_equal([@record.id], backend.read(cache_key))
  end

  def test_fetch_by_index_raises_when_called_on_a_scope
    Item.cache_index(:title)
    assert_raises(IdentityCache::UnsupportedScopeError) do
      Item.where(updated_at: nil).fetch_by_title("bob")
    end
  end

  def test_fetch_by_unique_index_raises_when_called_on_a_scope
    Item.cache_index(:title, :id, unique: true)
    assert_raises(IdentityCache::UnsupportedScopeError) do
      Item.where(updated_at: nil).fetch_by_title_and_id("bob", 2)
    end
  end

  def test_cache_index_on_derived_model_raises
    assert_raises(IdentityCache::DerivedModelError) do
      StiRecordTypeA.cache_index(:name, :id)
    end
  end

  def test_cache_index_with_non_id_primary_key
    KeyedRecord.cache_index(:value)
    KeyedRecord.create!(value: "a") { |r| r.hashed_key = 123 }
    assert_equal([123], KeyedRecord.fetch_by_value("a").map(&:id))
  end

  def test_unique_cache_index_with_non_id_primary_key
    KeyedRecord.cache_index(:value, unique: true)
    KeyedRecord.create!(value: "a") { |r| r.hashed_key = 123 }
    assert_equal(123, KeyedRecord.fetch_by_value("a").id)
  end

  private

  def cache_key(unique: false)
    "#{NAMESPACE}attr#{unique ? "" : "s"}:Item:id:title:#{cache_hash(@record.title.to_json)}"
  end
end
