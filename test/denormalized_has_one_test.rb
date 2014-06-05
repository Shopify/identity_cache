require "test_helper"

class DenormalizedHasOneTest < IdentityCache::TestCase
  def setup
    super
    Item.cache_has_one :associated
    Item.cache_index :title, :unique => true
    @record = Item.new(:title => 'foo')
    @record.associated = AssociatedRecord.new(:name => 'bar')
    @record.save

    @record.reload
  end

  def test_on_cache_miss_record_should_embed_associated_object
    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through

    record_from_cache_miss = Item.fetch_by_title('foo')

    assert_equal @record, record_from_cache_miss
    assert_not_nil @record.fetch_associated
    assert_equal @record.associated, record_from_cache_miss.fetch_associated
    assert fetch.has_been_called_with?(@record.secondary_cache_index_key_for_current_values([:title]))
    assert fetch.has_been_called_with?(@record.primary_cache_index_key)
  end

  def test_on_cache_miss_record_should_embed_nil_object

    @record.associated = nil
    @record.save!
    @record.reload
    @record.send(:populate_association_caches)
    Item.expects(:resolve_cache_miss).with(@record.id).once.returns(@record)

    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through

    record_from_cache_miss = Item.fetch_by_title('foo')
    record_from_cache_miss.expects(:associated).never

    assert_equal @record, record_from_cache_miss
    5.times do
      assert_nil record_from_cache_miss.fetch_associated
    end
    assert fetch.has_been_called_with?(@record.secondary_cache_index_key_for_current_values([:title]))
    assert fetch.has_been_called_with?(@record.primary_cache_index_key)
  end

  def test_on_record_from_the_db_will_use_normal_association
    record_from_db = Item.find_by_title('foo')

    assert_equal @record, record_from_db
    assert_not_nil record_from_db.fetch_associated
  end

  def test_on_cache_hit_record_should_come_back_with_cached_association
    @record.send(:populate_association_caches)
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)
    Item.fetch_by_title('foo')

    record_from_cache_hit = Item.fetch_by_title('foo')
    expected = @record.associated

    assert_equal @record, record_from_cache_hit
    assert_equal expected, record_from_cache_hit.fetch_associated
  end

  def test_on_cache_hit_record_should_come_back_with_cached_nil_association
    @record.associated = nil
    @record.save!
    @record.reload

    @record.send(:populate_association_caches)
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)
    Item.fetch_by_title('foo')

    record_from_cache_hit = Item.fetch_by_title('foo')
    record_from_cache_hit.expects(:associated).never

    assert_equal @record, record_from_cache_hit
    5.times do
      assert_nil record_from_cache_hit.fetch_associated
    end
  end

  def test_changes_in_associated_record_should_expire_the_parents_cache
    Item.fetch_by_title('foo')
    key = @record.primary_cache_index_key
    assert_not_nil IdentityCache.cache.fetch(key)

    IdentityCache.cache.expects(:delete).at_least(1).with(key)
    IdentityCache.cache.expects(:delete).with(@record.associated.primary_cache_index_key)

    @record.associated.save
  end

  def test_cached_associations_after_commit_hook_will_not_fail_on_undefined_parent_association
    ar = AssociatedRecord.new
    ar.save
    assert_nothing_raised { ar.expire_parent_cache }
  end

  def test_cache_without_guessable_inverse_name_raises
    assert_raises IdentityCache::InverseAssociationError do
      Item.cache_has_one :polymorphic_record, :embed => true
    end
  end

  def test_cache_without_guessable_inverse_name_does_not_raise_when_inverse_name_specified
    assert_nothing_raised do
      Item.cache_has_one :polymorphic_record, :inverse_name => :owner, :embed => true
    end
  end
end
