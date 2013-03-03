require "test_helper"

class NormalizedHasManyTest < IdentityCache::TestCase
  def setup
    super
    Record.cache_has_many :associated_records, :embed => false

    @record = Record.new(:title => 'foo')
    @record.associated_records << AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.save
    @record.reload
    @baz, @bar = @record.associated_records[0], @record.associated_records[1]
  end

  def test_a_records_list_of_associated_ids_on_the_parent_record_retains_association_sort_order
    assert_equal [2, 1], @record.associated_record_ids

    AssociatedRecord.create(name: 'foo', record_id: @record.id)
    @record.reload
    assert_equal [3, 2, 1], @record.associated_record_ids
  end

  def test_defining_a_denormalized_has_many_cache_caches_the_list_of_associated_ids_on_the_parent_record_during_cache_miss
    fetched_record = Record.fetch(@record.id)
    assert_equal [2, 1], fetched_record.cached_associated_record_ids
  end

  def test_the_cached_the_list_of_associated_ids_on_the_parent_record_should_not_be_populated_by_default
    assert_nil @record.cached_associated_record_ids
  end

  def test_fetching_the_association_should_fetch_each_record_by_id
    assert_equal [@baz, @bar], @record.fetch_associated_records
  end

  def test_fetching_the_association_from_a_identity_cached_record_should_not_re_fetch_the_association_ids
    @record = Record.fetch(@record.id)
    @record.expects(:associated_record_ids).never
    assert_equal [@baz, @bar], @record.fetch_associated_records
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_any_transaction_are_open
    @record = Record.fetch(@record.id)

    Record.expects(:fetch_multi).never
    @record.transaction do
      assert_equal [@baz, @bar], @record.fetch_associated_records
    end
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_the_normal_association_is_loaded
    # Warm the ActiveRecord association
    @record.associated_records.to_a

    Record.expects(:fetch_multi).never
    assert_equal [@baz, @bar], @record.fetch_associated_records
  end

  def test_saving_a_child_record_shouldnt_expire_the_parents_blob_if_the_foreign_key_hasnt_changed
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).never
    @baz.name = 'foo'
    @baz.save!
    assert_equal [@baz.id, @bar.id], Record.fetch(@record.id).cached_associated_record_ids
    assert_equal [@baz, @bar], Record.fetch(@record.id).fetch_associated_records
  end

  def test_creating_a_child_record_should_expire_the_parents_cache_blob
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    @qux = @record.associated_records.create!(:name => 'qux')
    assert_equal [@qux, @baz, @bar], Record.fetch(@record.id).fetch_associated_records
  end
  
  def test_saving_a_child_record_should_expire_the_new_and_old_parents_cache_blob
    @new_record = Record.create
    @baz.record_id = @new_record.id

    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@new_record.primary_cache_index_key).once

    @baz.save!

    assert_equal [@bar.id], Record.fetch(@record.id).cached_associated_record_ids
    assert_equal [@bar], Record.fetch(@record.id).fetch_associated_records
  end

  def test_saving_a_child_record_in_a_transaction_should_expire_the_new_and_old_parents_cache_blob
    @new_record = Record.create
    @baz.record_id = @new_record.id

    @baz.transaction do
      IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
      IdentityCache.cache.expects(:delete).with(@new_record.primary_cache_index_key).once

      @baz.save!
      @baz.reload
    end

    assert_equal [@bar.id], Record.fetch(@record.id).cached_associated_record_ids
    assert_equal [@bar], Record.fetch(@record.id).fetch_associated_records
  end

  def test_destroying_a_child_record_should_expire_the_parents_cache_blob
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key).once
    @baz.destroy
    assert_equal [@bar], @record.reload.fetch_associated_records
  end
end
