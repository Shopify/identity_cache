# frozen_string_literal: true
require "test_helper"

class AttributeCacheTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    AssociatedRecord.cache_attribute(:name)

    @parent = Item.create!(title: 'bob')
    @record = @parent.associated_records.create!(name: 'foo')
    @name_attribute_key = "#{NAMESPACE}attr:AssociatedRecord:name:id:#{cache_hash(@record.id.to_s.inspect)}"
    IdentityCache.cache.clear
  end

  def test_attribute_values_are_fetched_and_returned_on_cache_misses
    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through

    assert_queries(1) do
      assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
    end
    assert(fetch.has_been_called_with?(@name_attribute_key))
  end

  def test_attribute_values_are_returned_on_cache_hits
    assert_equal('foo', AssociatedRecord.fetch_name_by_id(1))

    assert_queries(0) do
      assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
    end
  end

  def test_nil_is_stored_in_the_cache_on_cache_misses
    assert_nil(AssociatedRecord.fetch_name_by_id(2))

    assert_queries(0) do
      assert_nil AssociatedRecord.fetch_name_by_id(2)
    end
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_is_saved
    assert_queries(1) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }
    assert_queries(0) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }

    @record.save!

    assert_queries(1) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_with_changed_attributes_is_saved
    assert_queries(1) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }
    assert_queries(0) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }

    @record.name = 'bar'
    @record.save!

    assert_queries(1) { assert_equal 'bar', AssociatedRecord.fetch_name_by_id(1) }
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_is_destroyed
    assert_queries(1) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }
    assert_queries(0) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1) }

    @record.destroy

    assert_queries(1) { assert_nil AssociatedRecord.fetch_name_by_id(1) }
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_a_new_record_is_saved
    new_id = 2
    assert_queries(1) { assert_nil AssociatedRecord.fetch_name_by_id(new_id) }
    assert_queries(0) { assert_nil AssociatedRecord.fetch_name_by_id(new_id) }

    @parent.associated_records.create(name: 'bar')

    assert_queries(1) { assert_equal 'bar', AssociatedRecord.fetch_name_by_id(new_id) }
  end

  def test_value_coercion
    assert_queries(1) { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(@record.id.to_f) }
    assert_no_queries { assert_equal 'foo', AssociatedRecord.fetch_name_by_id(@record.id) }
    @record.update!(name: 'bar')
    assert_queries(1) { assert_equal 'bar', AssociatedRecord.fetch_name_by_id(@record.id.to_f) }
  end

  def test_no_nil_empty_string_cache_key_conflict
    Item.cache_attribute(:id, by: [:title])
    @parent.update!(title: "")
    assert_queries(1) { assert_equal @parent.id, Item.fetch_id_by_title("") }
    assert_queries(1) { assert_nil Item.fetch_id_by_title(nil) }
    @parent.update!(title: nil)
    assert_queries(1) { assert_nil Item.fetch_id_by_title("") }
    assert_queries(1) { assert_equal @parent.id, Item.fetch_id_by_title(nil) }
  end

  def test_fetching_by_attribute_delegates_to_block_if_transactions_are_open
    IdentityCache.cache.expects(:read).never

    @record.transaction do
      assert_queries(1) do
        assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
      end
    end
  end

  def test_previously_stored_cached_nils_are_busted_by_new_record_saves
    assert_nil(AssociatedRecord.fetch_name_by_id(2))
    AssociatedRecord.create(name: "Jim")
    assert_equal("Jim", AssociatedRecord.fetch_name_by_id(2))
  end

  def test_cache_attribute_on_derived_model_raises
    assert_raises(IdentityCache::DerivedModelError) do
      StiRecordTypeA.cache_attribute(:name)
    end
  end

  def test_cache_attribute_respects_should_use_cache
    AssociatedRecord.stubs(:should_use_cache?).returns(false)

    assert_queries(1) do
      assert_memcache_operations(0) do
        AssociatedRecord.fetch_name_by_id(@record.id)
      end
    end
  end
end
