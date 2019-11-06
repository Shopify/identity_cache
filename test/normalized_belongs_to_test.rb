require "test_helper"

class NormalizedBelongsToTest < IdentityCache::TestCase
  def setup
    super
    AssociatedRecord.cache_belongs_to(:item)

    @parent_record = Item.new(title: 'foo')
    @parent_record.associated_records << AssociatedRecord.new(name: 'bar')
    @parent_record.save
    @parent_record.reload
    @record = @parent_record.associated_records.first
    # Reset association cache, so we remove the inverse of in memory reference
    @record.association(:item).reset
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_any_transactions_are_open
    Item.expects(:fetch_by_id).never
    @record.transaction do
      assert_equal @parent_record, @record.fetch_item
    end
  end

  def test_fetching_the_association_should_delegate_to_the_normal_association_fetcher_if_the_normal_association_is_loaded
    # Warm the ActiveRecord association
    @record.item

    Item.expects(:fetch_by_id).never
    assert_equal(@parent_record, @record.fetch_item)
  end

  def test_fetching_the_association_should_fetch_the_record_from_identity_cache
    Item.expects(:fetch_by_id).with(@parent_record.id).returns(@parent_record)
    assert_equal(@parent_record, @record.fetch_item)
  end

  def test_fetching_the_association_should_assign_the_result_to_an_instance_variable_so_that_successive_accesses_are_cached
    Item.expects(:fetch_by_id).with(@parent_record.id).returns(@parent_record)
    assert_equal(@parent_record, @record.fetch_item)
    assert_equal(false, @record.association(:item).loaded?)
    assert_equal(@parent_record, @record.fetch_item)
  end

  def test_fetching_the_association_should_cache_nil_and_not_raise_if_the_record_cant_be_found
    Item.expects(:fetch_by_id).with(@parent_record.id).returns(nil)
    assert_nil(@record.fetch_item) # miss
    assert_nil(@record.fetch_item) # hit
  end

  def test_cache_belongs_to_on_derived_model_raises
    assert_raises(IdentityCache::DerivedModelError) do
      StiRecordTypeA.cache_belongs_to(:item)
    end
  end

  def test_fetching_polymorphic_belongs_to_association
    PolymorphicRecord.include(IdentityCache)
    PolymorphicRecord.cache_belongs_to(:owner)
    PolymorphicRecord.create!(owner: @parent_record)

    assert_equal(@parent_record, PolymorphicRecord.first.fetch_owner)
  end

  def test_returned_record_should_be_readonly_on_cache_hit
    IdentityCache.with_fetch_read_only_records do
      @record.fetch_item # warm cache
      assert @record.fetch_item.readonly?
      refute @record.item.readonly?
    end
  end

  def test_returned_record_should_be_readonly_on_cache_miss
    IdentityCache.with_fetch_read_only_records do
      assert @record.fetch_item.readonly?
      refute @record.item.readonly?
    end
  end

  def test_db_returned_record_should_never_be_readonly
    IdentityCache.with_fetch_read_only_records do
      uncached_record = @record.item
      refute uncached_record.readonly?
      @record.fetch_item
      refute uncached_record.readonly?
    end
  end

  def test_returned_record_with_open_transactions_should_not_be_readonly
    IdentityCache.with_fetch_read_only_records do
      Item.transaction do
        refute IdentityCache.should_use_cache?
        refute @record.fetch_item.readonly?
      end
    end
  end

  def test_respects_should_use_cache_on_parent
    @record.reload
    @parent_record.class.stubs(:should_use_cache?).returns(false)

    assert_queries(1) do
      assert_memcache_operations(0) do
        @record.fetch_item
      end
    end
  end

  def test_cache_belongs_to_with_scope
    AssociatedRecord.belongs_to(:item_with_scope, -> { where.not(timestamp: nil) },
      class_name: 'Item', foreign_key: 'item_id')
    assert_raises(IdentityCache::UnsupportedAssociationError) do
      AssociatedRecord.cache_belongs_to(:item_with_scope)
    end
  end
end
