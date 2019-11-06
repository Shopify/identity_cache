require "test_helper"

class DenormalizedHasManyTest < IdentityCache::TestCase
  def setup
    super
    PolymorphicRecord.include(IdentityCache::WithoutPrimaryIndex)
    Item.cache_has_many(:associated_records, :embed => true)

    @record = Item.new(:title => 'foo')
    @record.associated_records << AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.save
    @record.reload
  end

  def test_uncached_record_from_the_db_should_come_back_with_association_array
    record_from_db = Item.find(@record.id)
    assert_equal(Array, record_from_db.fetch_associated_records.class)
  end

  def test_uncached_record_from_the_db_will_use_normal_association
    expected = @record.associated_records
    record_from_db = Item.find(@record.id)

    Item.any_instance.expects(:association).with(:associated_records).returns(expected)

    assert_equal(@record, record_from_db)
    assert_equal(expected, record_from_db.fetch_associated_records)
  end

  def test_on_cache_hit_record_should_come_back_with_cached_association_array
    Item.fetch(@record.id) # warm cache

    record_from_cache_hit = Item.fetch(@record.id)
    assert_equal(@record, record_from_cache_hit)
    assert_equal(Array, record_from_cache_hit.fetch_associated_records.class)
  end

  def test_on_cache_hit_record_should_come_back_with_cached_association
    Item.fetch(@record.id) # warm cache

    record_from_cache_hit = Item.fetch(@record.id)
    assert_equal(@record, record_from_cache_hit)

    result = assert_memcache_operations(0) do
      assert_no_queries do
        record_from_cache_hit.fetch_associated_records
      end
    end

    assert_equal(@record.associated_records, result)
  end

  def test_on_cache_miss_record_should_embed_associated_objects_and_return
    record_from_cache_miss = Item.fetch(@record.id)
    expected = @record.associated_records

    assert_equal(@record, record_from_cache_miss)
    assert_equal(expected, record_from_cache_miss.fetch_associated_records)
    assert_equal(false, record_from_cache_miss.associated_records.loaded?)
  end

  def test_delegate_to_normal_association_if_loaded
    Item.fetch(@record.id) # warm cache
    item = Item.fetch(@record.id)
    item.fetch_associated_records

    item.associated_records << AssociatedRecord.new(:name => 'buzz')
    assert_equal(item.associated_records.to_a, item.fetch_associated_records)
  end

  def test_changes_in_associated_records_should_expire_the_parents_cache
    Item.fetch(@record.id)
    key = @record.primary_cache_index_key
    assert_not_nil(IdentityCache.cache.fetch(key))

    IdentityCache.cache.expects(:delete).with(@record.associated_records.first.primary_cache_index_key)
    IdentityCache.cache.expects(:delete).with(key)
    @record.associated_records.first.save
  end

  def test_changes_in_associated_records_foreign_keys_should_expire_new_parent_and_old_parents_cache
    @associatated_record = @record.associated_records.first
    old_key = @record.primary_cache_index_key
    @new_record = Item.create!
    new_key = @new_record.primary_cache_index_key

    IdentityCache.cache.expects(:delete).with(@associatated_record.primary_cache_index_key)
    IdentityCache.cache.expects(:delete).with(old_key)
    IdentityCache.cache.expects(:delete).with(new_key)
    @associatated_record.item = @new_record
    @associatated_record.save!
  end

  def test_cached_associations_after_commit_hook_will_not_fail_on_undefined_parent_association
    ar = AssociatedRecord.new
    ar.save
    assert_nothing_raised { ar.expire_parent_caches }
  end

  def test_cache_without_guessable_inverse_name_raises
    assert_raises IdentityCache::InverseAssociationError do
      Item.cache_has_many(:no_inverse_of_records, :embed => true)
      IdentityCache.eager_load!
    end
  end

  def test_cache_without_guessable_inverse_name_does_not_raise_when_inverse_name_specified
    assert_nothing_raised do
      Item.cache_has_many(:no_inverse_of_records, :inverse_name => :owner, :embed => true)
      IdentityCache.eager_load!
    end
  end

  def test_cache_uses_inverse_of_on_association
    Item.has_many(:invertable_association, :inverse_of => :owner, :class_name => 'PolymorphicRecord', :as => "owner")
    Item.cache_has_many(:invertable_association, :embed => true)
    IdentityCache.eager_load!
  end

  def test_saving_associated_records_should_expire_itself_and_the_parents_cache
    child = @record.associated_records.first
    IdentityCache.cache.expects(:delete).with(child.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key)
    child.save!
  end

  def test_fetch_association_does_not_allow_chaining
    check = proc { assert_equal false, Item.fetch(@record.id).fetch_associated_records.respond_to?(:where) }
    2.times { check.call } # for miss and hit
    Item.transaction { check.call }
  end

  def test_never_set_inverse_association_on_cache_hit
    Item.fetch(@record.id) # warm cache

    item = Item.fetch(@record.id)

    associated_record = item.fetch_associated_records.to_a.first
    refute_equal(item.object_id, associated_record.item.object_id)
  end

  def test_returned_records_should_be_readonly_on_cache_hit
    IdentityCache.with_fetch_read_only_records do
      Item.fetch(@record.id) # warm cache
      record_from_cache_hit = Item.fetch(@record.id)
      assert record_from_cache_hit.fetch_associated_records.all?(&:readonly?)
    end
  end

  def test_returned_records_should_be_readonly_on_cache_miss
    IdentityCache.with_fetch_read_only_records do
      record_from_cache_miss = Item.fetch(@record.id)
      assert record_from_cache_miss.fetch_associated_records.all?(&:readonly?)
    end
  end

  def test_db_returned_records_should_never_be_readonly
    IdentityCache.with_fetch_read_only_records do
      record_from_db = Item.find(@record.id)
      uncached_records = record_from_db.associated_records
      assert uncached_records.none?(&:readonly?)
      assert record_from_db.fetch_associated_records.none?(&:readonly?)
      assert record_from_db.associated_records.none?(&:readonly?)
    end
  end

  def test_returned_records_with_open_transactions_should_not_be_readonly
    IdentityCache.with_fetch_read_only_records do
      Item.transaction do
        assert_equal IdentityCache.should_use_cache?, false
        assert Item.fetch(@record.id).fetch_associated_records.none?(&:readonly?)
      end
    end
  end

  def test_respect_should_use_cache_from_embedded_records
    Item.fetch(@record.id)
    AssociatedRecord.stubs(:should_use_cache?).returns(false)

    assert_memcache_operations(1) do
      assert_queries(1) do
        Item.fetch(@record.id).fetch_associated_records
      end
    end
  end

  class CheckAssociationTest < IdentityCache::TestCase
    def test_unsupported_through_assocation
      assert_raises IdentityCache::UnsupportedAssociationError, "caching through associations isn't supported" do
        Item.has_many(:deeply_through_associated_records, :through => :associated_records, foreign_key: 'associated_record_id', inverse_of: :item, :class_name => 'DeeplyAssociatedRecord')
        Item.cache_has_many(:deeply_through_associated_records, :embed => true)
      end
    end

    def test_unsupported_joins_in_assocation_scope
      scope = -> { joins(:associated_record).where(associated_records: { name: 'contrived example' }) }
      Item.has_many(:deeply_joined_associated_records, scope, inverse_of: :item, class_name: 'DeeplyAssociatedRecord')
      Item.cache_has_many(:deeply_joined_associated_records, :embed => true)

      message = "caching association Item.deeply_joined_associated_records scoped with a join isn't supported"
      assert_raises IdentityCache::UnsupportedAssociationError, message do
        Item.fetch(1)
      end
    end

    def test_cache_has_many_on_derived_model_raises
      assert_raises(IdentityCache::DerivedModelError) do
        StiRecordTypeA.cache_has_many(:polymorphic_records, :inverse_name => :owner, :embed => true)
      end
    end
  end
end
