require "test_helper"

class NormalizedHasManyTest < IdentityCache::TestCase
  def setup
    super
    Item.cache_has_many :associated_records, :embed => :ids

    @record = Item.new(:title => 'foo')
    @record.not_cached_records << NotCachedRecord.new(:name => 'NoCache')
    @record.associated_records << AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.save
    @record.reload
    @baz, @bar  = @record.associated_records[0], @record.associated_records[1]
    @not_cached = @record.not_cached_records.first
  end

  def test_a_records_list_of_associated_ids_on_the_parent_record_retains_association_sort_order
    assert_equal [2, 1], @record.associated_record_ids

    AssociatedRecord.create(name: 'foo', item_id: @record.id)
    @record.reload
    assert_equal [3, 2, 1], @record.associated_record_ids
  end

  def test_defining_a_denormalized_has_many_cache_caches_the_list_of_associated_ids_on_the_parent_record_during_cache_miss
    fetched_record = Item.fetch(@record.id)
    assert_equal [2, 1], fetched_record.cached_associated_record_ids
    assert_equal false, fetched_record.associated_records.loaded?
  end

  def test_batch_fetching_of_association_for_multiple_parent_records
    record2 = Item.new(:title => 'two')
    record2.associated_records << AssociatedRecord.new(:name => 'a')
    record2.associated_records << AssociatedRecord.new(:name => 'b')
    record2.save!

    fetched_records = assert_queries(2) do
      Item.fetch_multi(@record.id, record2.id)
    end
    assert_equal [[2, 1], [4, 3]], fetched_records.map(&:cached_associated_record_ids)
    assert_equal false, fetched_records.any?{ |record| record.associated_records.loaded? }
  end

  def test_batch_fetching_of_deeply_associated_records
    Item.has_many :denormalized_associated_records, class_name: 'AssociatedRecord'
    Item.cache_has_many :denormalized_associated_records, embed: true
    AssociatedRecord.cache_has_many :deeply_associated_records, embed: :ids
    @record.associated_records[0].deeply_associated_records << DeeplyAssociatedRecord.new(:name => 'deep1')
    @record.associated_records[1].deeply_associated_records << DeeplyAssociatedRecord.new(:name => 'deep2')
    @record.associated_records.each(&:save!)

    fetched_records = assert_queries(4) do
      Item.fetch(@record.id)
    end
    assert_no_queries do
      assert_equal [[1], [2]], fetched_records.fetch_denormalized_associated_records.map(&:cached_deeply_associated_record_ids)
      assert_equal false, fetched_records.fetch_denormalized_associated_records.any?{ |record| record.deeply_associated_records.loaded? }
    end
  end

  def test_fetching_associated_ids_will_populate_the_value_if_the_record_isnt_from_the_cache
    assert_equal [2, 1], @record.fetch_associated_record_ids
    assert_no_queries do
      assert_equal [2, 1], @record.fetch_associated_record_ids
    end
  end

  def test_fetching_associated_ids_will_use_the_cached_value_if_the_record_is_from_the_cache
    @record = Item.fetch(@record.id)
    assert_queries(0) do
      assert_equal [2, 1], @record.fetch_associated_record_ids
    end
  end

  def test_the_cached_the_list_of_associated_ids_on_the_parent_record_should_not_be_populated_by_default
    assert_nil @record.cached_associated_record_ids
  end

  def test_fetching_the_association_should_fetch_each_record_by_id
    assert_equal [@baz, @bar], @record.fetch_associated_records
  end

  def test_record_from_the_db_will_fetch_associations_from_cache_on_hit
    Item.fetch(@record.id)
    record_from_db = Item.find(@record.id)
    assert_no_queries do
      assert_equal [2, 1], record_from_db.fetch_associated_record_ids
    end
  end

  def test_fetching_the_association_from_a_record_on_a_cache_hit_should_not_issue_any_queries
    # Populate the cache
    @record = Item.fetch(@record.id)
    @record.fetch_associated_records
    assert_queries(0) do
      @record = Item.fetch(@record.id)
      assert_equal [@baz, @bar], @record.fetch_associated_records
    end
  end

  def test_fetching_the_association_from_a_identity_cached_record_should_not_re_fetch_the_association_ids
    @record = Item.fetch(@record.id)
    @record.expects(:associated_record_ids).never
    assert_equal [@baz, @bar], @record.fetch_associated_records
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_any_transaction_are_open
    @record = Item.fetch(@record.id)

    Item.expects(:fetch_multi).never
    @record.transaction do
      assert_equal [@baz, @bar], @record.fetch_associated_records
    end
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_the_normal_association_is_loaded
    # Warm the ActiveRecord association
    @record.associated_records.to_a

    Item.expects(:fetch_multi).never
    assert_equal [@baz, @bar], @record.fetch_associated_records
  end

  def test_saving_a_child_record_shouldnt_expire_the_parents_blob_if_the_foreign_key_hasnt_changed
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).never
    IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key)
    @baz.name = 'foo'
    @baz.save!
    assert_equal [@baz.id, @bar.id], Item.fetch(@record.id).cached_associated_record_ids
    assert_equal [@baz, @bar], Item.fetch(@record.id).fetch_associated_records
  end

  def test_creating_a_child_record_should_expire_the_parents_cache_blob
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@bar.primary_cache_index_key[0...-1] + '3')
    @qux = @record.associated_records.create!(:name => 'qux')
    assert_equal [@qux, @baz, @bar], Item.fetch(@record.id).fetch_associated_records
  end

  def test_saving_a_child_record_should_expire_the_new_and_old_parents_cache_blob
    @new_record = Item.create
    @baz.item = @new_record

    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@new_record.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key).once

    @baz.save!

    assert_equal [@bar.id], Item.fetch(@record.id).cached_associated_record_ids
    assert_equal [@bar], Item.fetch(@record.id).fetch_associated_records
  end

  def test_saving_a_child_record_in_a_transaction_should_expire_the_new_and_old_parents_cache_blob
    @new_record = Item.create
    @baz.item_id = @new_record.id

    @baz.transaction do
      IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
      IdentityCache.cache.expects(:delete).with(@new_record.primary_cache_index_key).once
      IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key).once

      @baz.save!
      @baz.reload
    end

    assert_equal [@bar.id], Item.fetch(@record.id).cached_associated_record_ids
    assert_equal [@bar], Item.fetch(@record.id).fetch_associated_records
  end

  def test_destroying_a_child_record_should_expire_the_parents_cache_blob
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key).once
    @baz.destroy
    assert_equal [@bar], @record.reload.fetch_associated_records
  end

  def test_saving_a_child_record_should_expire_only_itself
    IdentityCache.cache.expects(:delete).with(@baz.primary_cache_index_key).once
    @baz.save!
  end

  def test_touching_child_with_touch_true_on_parent_expires_parent
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    @not_cached.touch
  end

  def test_saving_child_with_touch_true_on_parent_expires_parent
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    @not_cached.name = 'Changed'
    @not_cached.save!
  end

end
