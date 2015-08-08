require "test_helper"

class DenormalizedHasManyTest < IdentityCache::TestCase
  def setup
    super
    Item.cache_has_many :associated_records, :embed => true

    @record = Item.new(:title => 'foo')
    @record.associated_records << AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.save
    @record.reload
  end

  def test_uncached_record_from_the_db_will_use_normal_association
    expected = @record.associated_records
    record_from_db = Item.find(@record.id)

    Item.any_instance.expects(:associated_records).returns(expected)

    assert_equal @record, record_from_db
    assert_equal expected, record_from_db.fetch_associated_records
  end

  def test_on_cache_hit_record_should_come_back_with_cached_association
    Item.fetch(@record.id) # warm cache

    record_from_cache_hit = Item.fetch(@record.id)
    assert_equal @record, record_from_cache_hit

    expected = @record.associated_records
    Item.any_instance.expects(:associated_records).never
    assert_equal expected, record_from_cache_hit.fetch_associated_records
  end

  def test_on_cache_miss_record_should_embed_associated_objects_and_return
    record_from_cache_miss = Item.fetch(@record.id)
    expected = @record.associated_records

    assert_equal @record, record_from_cache_miss
    assert_equal expected, record_from_cache_miss.fetch_associated_records
  end

  def test_changes_in_associated_records_should_expire_the_parents_cache
    Item.fetch(@record.id)
    key = @record.primary_cache_index_key
    assert_not_nil IdentityCache.cache.fetch(key)

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
      Item.cache_has_many :polymorphic_records, :embed => true
    end
  end

  def test_cache_without_guessable_inverse_name_does_not_raise_when_inverse_name_specified
    assert_nothing_raised do
      Item.cache_has_many :polymorphic_records, :inverse_name => :owner, :embed => true
    end
  end

  def test_cache_uses_inverse_of_on_association
    Item.has_many :invertable_association, :inverse_of => :owner, :class_name => 'PolymorphicRecord', :as => "owner", :inverse_of => :owner
    Item.cache_has_many :invertable_association, :embed => true
  end

  def test_saving_associated_records_should_expire_itself_and_the_parents_cache
    child = @record.associated_records.first
    IdentityCache.cache.expects(:delete).with(child.primary_cache_index_key).once
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key)
    child.save!
  end
end
