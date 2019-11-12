# frozen_string_literal: true
require "test_helper"

class NormalizedHasOneTest < IdentityCache::TestCase
  def setup
    super
    Item.cache_has_one(:associated, embed: :id)

    @record = Item.new(title: 'foo')
    @record.build_associated(name: 'bar')
    @record.save!
    @record.reload
    @baz = @record.associated
  end

  def test_not_implemented_error
    assert_raises(NotImplementedError) do
      Item.cache_has_one(:associated, embed: false)
    end
  end

  def test_defining_a_denormalized_has_one_cache_caches_the_associated_id_on_the_parent_record_during_cache_miss
    fetched_record = Item.fetch(@record.id)
    assert_equal(1, fetched_record.cached_associated_id)
    refute_predicate(fetched_record.association(:associated), :loaded?)
  end

  def test_batch_fetching_of_association_for_multiple_parent_records
    record2 = Item.new(title: 'two')
    record2.build_associated(name: 'a')
    record2.save!

    fetched_records = assert_queries(2) do
      Item.fetch_multi(@record.id, record2.id)
    end
    assert_equal([1, 2], fetched_records.map(&:cached_associated_id))

    fetched_records.each do |record|
      refute_predicate record.association(:associated), :loaded?
    end
  end

  def test_batch_fetching_of_deeply_associated_records
    Item.has_one(:denormalized_associated, class_name: 'AssociatedRecord')
    Item.cache_has_one(:denormalized_associated, embed: true)
    AssociatedRecord.cache_has_one(:deeply_associated, embed: :id)

    @record.associated.build_deeply_associated(name: 'deep1')
    @record.associated.save!

    fetched_record = assert_queries(4) do
      Item.fetch(@record.id)
    end

    assert_no_queries do
      assert_equal 1, fetched_record.fetch_denormalized_associated.cached_deeply_associated_id
      refute_predicate fetched_record.fetch_denormalized_associated.association(:deeply_associated), :loaded?
    end
  end

  def test_fetching_associated_id_will_populate_the_value_if_the_record_isnt_from_the_cache
    assert_equal(1, @record.fetch_associated_id)
  end

  def test_fetching_associated_id_will_use_the_cached_value_if_the_record_is_from_the_cache
    @record = Item.fetch(@record.id)
    assert_queries(0) do
      assert_equal 1, @record.fetch_associated_id
    end
  end

  def test_the_cached_associated_id_on_the_parent_record_should_not_be_populated_by_default
    assert_nil(@record.cached_associated_id)
  end

  def test_fetching_the_association_should_fetch_each_record_by_id
    assert_equal(@baz, @record.fetch_associated)
  end

  def test_fetching_the_association_from_a_record_on_a_cache_hit_should_not_issue_any_queries
    # Populate the cache
    @record = Item.fetch(@record.id)
    @record.fetch_associated
    assert_queries(0) do
      @record = Item.fetch(@record.id)
      assert_equal @baz, @record.fetch_associated
    end
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_any_transaction_are_open
    @record = Item.fetch(@record.id)

    assert_memcache_operations(0) do
      @record.transaction do
        assert_equal @baz, @record.fetch_associated
      end
    end
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_the_normal_association_is_loaded
    # Warm the ActiveRecord association
    @record.associated

    assert_memcache_operations(0) do
      assert_equal @baz, @record.fetch_associated
    end
  end

  def test_saving_the_child_shouldnt_expire_the_parent_blob_if_the_foreign_key_hasnt_changed
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).never
    IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key)
    @baz.name = 'foo'
    @baz.save!
    assert_equal(@baz.id, Item.fetch(@record.id).cached_associated_id)
    assert_equal(@baz, Item.fetch(@record.id).fetch_associated)
  end

  def test_saving_the_child_in_a_transaction_should_expire_the_new_and_old_parents_cache_blob
    @new_record = Item.create
    @baz.item_id = @new_record.id

    @baz.transaction do
      IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key)
      IdentityCache.cache.expects(:delete).with(@new_record.primary_cache_index_key)
      IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key)

      @baz.save!
      @baz.reload
    end

    assert_nil(Item.fetch(@record.id).cached_associated_id)
    assert_nil(Item.fetch(@record.id).fetch_associated)
  end

  def test_saving_a_child_record_should_expire_only_itself
    IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key).once
    @baz.save!
  end

  def test_returned_records_should_be_readonly_on_cache_hit
    IdentityCache.with_fetch_read_only_records do
      Item.fetch(@record.id) # warm cache
      record_from_cache_hit = Item.fetch(@record.id)
      record_from_cache_hit.fetch_associated.readonly?
    end
  end

  def test_returned_record_should_be_readonly_on_cache_miss
    IdentityCache.with_fetch_read_only_records do
      record_from_cache_miss = Item.fetch(@record.id)
      assert record_from_cache_miss.fetch_associated.readonly?
    end
  end

  def test_respects_should_use_cache_on_association
    @record.reload
    AssociatedRecord.stubs(:should_use_cache?).returns(false)

    assert_queries(1) do
      assert_memcache_operations(0) do
        @record.fetch_associated
      end
    end
  end
end
