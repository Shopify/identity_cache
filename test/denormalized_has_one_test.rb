# frozen_string_literal: true
require "test_helper"

class DenormalizedHasOneTest < IdentityCache::TestCase
  def setup
    super
    PolymorphicRecord.include(IdentityCache::WithoutPrimaryIndex)
    Item.cache_has_one(:associated)
    Item.cache_index(:title, unique: true)
    @record = Item.new(title: 'foo')
    @record.associated = AssociatedRecord.new(name: 'bar')
    @record.save

    @record.reload
  end

  def test_on_cache_miss_record_should_embed_associated_object
    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through

    record_from_cache_miss = Item.fetch_by_title('foo')

    assert_equal(@record, record_from_cache_miss)
    assert_not_nil(@record.fetch_associated)
    assert_equal(@record.associated, record_from_cache_miss.fetch_associated)
    assert(fetch.has_been_called_with?(@record.attribute_cache_key_for_attribute_and_current_values(:id, [:title], true)))
    assert(fetch.has_been_called_with?(@record.primary_cache_index_key))
  end

  def test_on_cache_miss_record_should_embed_nil_object

    @record.associated = nil
    @record.save!
    @record.reload
    Item.expects(:resolve_cache_miss).with(@record.id).once.returns(@record)

    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through

    record_from_cache_miss = Item.fetch_by_title('foo')
    record_from_cache_miss.expects(:associated).never

    assert_equal(@record, record_from_cache_miss)
    5.times do
      assert_nil record_from_cache_miss.fetch_associated
    end
    assert(fetch.has_been_called_with?(@record.attribute_cache_key_for_attribute_and_current_values(:id, [:title], true)))
    assert(fetch.has_been_called_with?(@record.primary_cache_index_key))
  end

  def test_on_record_from_the_db_will_use_normal_association
    record_from_db = Item.find_by_title('foo')

    assert_equal(@record, record_from_db)
    assert_not_nil(record_from_db.fetch_associated)
  end

  def test_on_cache_hit_record_should_come_back_with_cached_association
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)
    Item.fetch_by_title('foo')

    record_from_cache_hit = Item.fetch_by_title('foo')
    expected = @record.associated

    assert_equal(@record, record_from_cache_hit)
    assert_equal(expected, record_from_cache_hit.fetch_associated)
  end


  def test_on_cache_hit_record_must_invoke_listener
    payloads = []
    subscriber = ActiveSupport::Notifications.subscribe('hydration.identity_cache') do |_, _, _, _, payload|
      payloads << payload
    end

    _miss = Item.fetch_by_title('foo')
    assert_equal(0, payloads.length)

    hit = Item.fetch_by_title('foo')
    assert_equal(1, payloads.length)
    assert_equal({ class: "Item" }, payloads.pop)

    assert_equal(@record.associated, hit.fetch_associated)
    assert_equal(1, payloads.length)
    assert_equal({ class: "AssociatedRecord" }, payloads.pop)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_on_cache_hit_record_should_come_back_with_cached_nil_association
    @record.associated = nil
    @record.save!
    @record.reload

    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)
    Item.fetch_by_title('foo')

    record_from_cache_hit = Item.fetch_by_title('foo')
    record_from_cache_hit.expects(:associated).never

    assert_equal(@record, record_from_cache_hit)
    5.times do
      assert_nil record_from_cache_hit.fetch_associated
    end
  end

  def test_changes_in_associated_record_should_expire_the_parents_cache
    Item.fetch_by_title('foo')
    key = @record.primary_cache_index_key
    assert_not_nil(IdentityCache.cache.fetch(key))

    IdentityCache.cache.expects(:delete).at_least(1).with(key)
    IdentityCache.cache.expects(:delete).with(@record.associated.primary_cache_index_key)

    @record.associated.save
  end

  def test_cached_associations_after_commit_hook_will_not_fail_on_undefined_parent_association
    ar = AssociatedRecord.new
    ar.save
    assert_nothing_raised { ar.expire_parent_caches }
  end

  def test_set_inverse_cached_association
    AssociatedRecord.cache_belongs_to(:item)
    Item.fetch(@record.id) # warm cache
    item = Item.fetch(@record.id)

    assert_no_queries do
      assert_memcache_operations(0) do
        item.fetch_associated.fetch_item
      end
    end
  end

  def test_cache_without_guessable_inverse_name_raises
    assert_raises IdentityCache::InverseAssociationError do
      Item.cache_has_one(:no_inverse_of_record, embed: true)
      IdentityCache.eager_load!
    end
  end

  def test_cache_without_guessable_inverse_name_does_not_raise_when_inverse_name_specified
    assert_nothing_raised do
      Item.cache_has_one(:no_inverse_of_record, inverse_name: :owner, embed: true)
      IdentityCache.eager_load!
    end
  end

  def test_unsupported_through_assocation
    assert_raises IdentityCache::UnsupportedAssociationError, "caching through associations isn't supported" do
      Item.has_one(:deeply_associated, through: :associated, class_name: 'DeeplyAssociatedRecord')
      Item.cache_has_one(:deeply_associated, embed: true)
    end
  end

  def test_cache_has_one_on_derived_model_raises
    assert_raises(IdentityCache::DerivedModelError) do
      StiRecordTypeA.cache_has_one(:polymorphic_record, inverse_name: :owner, embed: true)
    end
  end

  def test_returned_record_should_be_readonly_on_cache_hit
    IdentityCache.with_fetch_read_only_records do
      Item.fetch_by_title('foo')
      record_from_cache_hit = Item.fetch_by_title('foo')
      assert record_from_cache_hit.fetch_associated.readonly?
      refute record_from_cache_hit.associated.readonly?
    end
  end

  def test_returned_record_should_be_readonly_on_cache_miss
    IdentityCache.with_fetch_read_only_records do
      assert IdentityCache.should_use_cache?
      record_from_cache_miss = Item.fetch_by_title('foo')
      assert record_from_cache_miss.fetch_associated.readonly?
    end
  end

  def test_db_returned_record_should_never_be_readonly
    IdentityCache.with_fetch_read_only_records do
      record_from_db = Item.find_by_title('foo')
      uncached_record = record_from_db.associated
      refute uncached_record.readonly?
      record_from_db.fetch_associated
      refute uncached_record.readonly?
    end
  end

  def test_returned_record_with_open_transactions_should_not_be_readonly
    IdentityCache.with_fetch_read_only_records do
      Item.transaction do
        refute IdentityCache.should_use_cache?
        refute Item.fetch_by_title('foo').fetch_associated.readonly?
      end
    end
  end
end
