# frozen_string_literal: true
require "test_helper"

class CacheInvalidationTest < IdentityCache::TestCase
  def setup
    super

    @record = Item.new(title: 'foo')
    @record.associated_records << AssociatedRecord.new(name: 'bar')
    @record.associated_records << AssociatedRecord.new(name: 'baz')
    @record.save!
    @record.reload
    @baz = @record.associated_records[0]
    @bar = @record.associated_records[1]
    @record.reload
  end

  def test_reload_invalidate_cached_ids
    Item.cache_has_many(:associated_records, embed: :ids)

    variable_name = @record.class.send(:embedded_associations)[:associated_records].ids_variable_name

    @record.fetch_associated_record_ids
    assert_equal([@baz.id, @bar.id], @record.instance_variable_get(variable_name))

    @record.reload
    assert_equal(false, @record.instance_variable_defined?(variable_name))

    @record.fetch_associated_record_ids
    assert_equal([@baz.id, @bar.id], @record.instance_variable_get(variable_name))
  end

  def test_reload_invalidate_cached_objects
    Item.cache_has_many(:associated_records, embed: :ids)

    variable_name = @record.class.send(:embedded_associations)[:associated_records].records_variable_name

    @record.fetch_associated_records
    assert_equal([@baz, @bar], @record.instance_variable_get(variable_name))

    @record.reload
    assert_equal(false, @record.instance_variable_defined?(variable_name))

    @record.fetch_associated_records
    assert_equal([@baz, @bar], @record.instance_variable_get(variable_name))
  end

  def test_reload_cache_ids
    Item.cache_has_many(:associated_records, embed: :ids)

    assert_equal([@baz, @bar], @record.fetch_associated_records)
    assert_equal([@baz, @bar], @record.associated_records)

    @baz.destroy
    @record.reload

    assert_equal([@bar], @record.fetch_associated_records)
    assert_equal([@bar], @record.associated_records)
  end

  def test_reload_cache_id
    Item.cache_has_one(:associated, embed: :id)

    assert_equal(@baz, @record.fetch_associated)
    assert_equal(@baz, @record.associated)

    @baz.destroy
    @record.reload

    assert_equal(@bar, @record.fetch_associated)
    assert_equal(@bar, @record.associated)
  end

  def test_cache_invalidation_expire_properly_if_child_is_embed_in_multiple_parents
    Item.cache_has_many(:associated_records, embed: true)
    ItemTwo.cache_has_many(:associated_records, embed: true)

    baz = AssociatedRecord.new(name: 'baz')

    record1 = Item.new(title: 'foo')
    record1.associated_records << baz
    record1.save!

    record2 = ItemTwo.new(title: 'bar')
    record2.associated_records << baz
    record2.save!

    record1.class.fetch(record1.id)
    record2.class.fetch(record2.id)

    expected_keys = [
      record1.primary_cache_index_key,
      record2.primary_cache_index_key,
    ]

    expected_keys.each do |expected_key|
      assert(IdentityCache.cache.fetch(expected_key) { nil })
    end

    baz.update!(updated_at: baz.updated_at + 1)

    expected_keys.each do |expected_key|
      refute(IdentityCache.cache.fetch(expected_key) { nil })
    end
  end

  def test_cache_invalidation_expire_properly_if_child_is_embed_in_multiple_parents_with_ids
    Item.cache_has_many(:associated_records, embed: :ids)
    ItemTwo.cache_has_many(:associated_records, embed: :ids)

    baz = AssociatedRecord.new(name: 'baz')

    record1 = Item.new(title: 'foo')
    record1.save

    record2 = ItemTwo.new(title: 'bar')
    record2.save

    record1.class.fetch(record1.id)
    record2.class.fetch(record2.id)

    expected_keys = [
      record1.primary_cache_index_key,
      record2.primary_cache_index_key,
    ]

    expected_keys.each do |expected_key|
      assert(IdentityCache.cache.fetch(expected_key) { nil })
    end

    baz.item = record1
    baz.item_two = record2
    baz.save!

    expected_keys.each do |expected_key|
      refute(IdentityCache.cache.fetch(expected_key) { nil })
    end
  end

  def test_cache_invalidation_expire_properly_when_expired_via_class_method
    record = Item.create(title: 'foo')
    record.class.fetch(record.id)

    refute_nil(IdentityCache.cache.fetch(record.primary_cache_index_key) { nil })

    Item.expire_primary_key_cache_index(record.id)

    assert_nil(IdentityCache.cache.fetch(record.primary_cache_index_key) { nil })
  end

  def test_dedup_cache_invalidation_of_records_embedded_twice_through_different_associations
    Item.cache_has_many(:associated_records, embed: true)
    AssociatedRecord.cache_has_many(:deeply_associated_records, embed: true)
    Item.cache_has_many(:deeply_associated_records, embed: true)

    deeply_associated_record = DeeplyAssociatedRecord.new(name: 'deep', item_id: @record.id)
    @record.associated_records[0].deeply_associated_records << deeply_associated_record
    deeply_associated_record.reload

    Item.any_instance.expects(:expire_primary_index).once

    deeply_associated_record.name = "deep2"
    deeply_associated_record.save!
  end

  def test_cache_invalidation_skipped_if_no_columns_change
    @record.class.fetch(@record.id) # fill cache
    @record.update!(title: @record.title)
    assert_no_queries do
      @record.class.fetch(@record.id)
    end
  end

  def test_cache_parent_invalidation_skipped_if_no_columns_change
    Item.cache_has_many(:associated_records, embed: true)
    @record.class.fetch(@record.id) # fill cache

    child = @record.associated_records.first
    child.update!(name: child.name)

    assert_no_queries do
      @record.class.fetch(@record.id)
    end
  end

  def test_cache_expiry_before_other_after_commit_callbacks
    Item.fetch(@record.id) # fill cache

    record_id = @record.id
    after_commit_fetched = nil
    Item.after_commit do
      after_commit_fetched = Item.fetch(record_id)
    end
    @record.update!(updated_at: @record.updated_at + 1)

    assert_equal(after_commit_fetched.updated_at, @record.updated_at)
  end

  def test_cache_not_expired_until_after_transaction
    log = []
    subscribe_to_sql_queries(->(sql) { log << [:sql, sql] }) do
      subscribe_to_cache_operations(->(op) { log << [:cache, op] }) do
        @record.update!(title: 'foo2')
      end
    end
    assert_equal([:sql, :sql, :sql, :cache], log.map(&:first))
    sql_queries = log.first(3).map(&:last)
    assert_match(/^BEGIN\b/, sql_queries[0])
    assert_match(/^UPDATE\b/, sql_queries[1])
    assert_match(/^COMMIT\b/, sql_queries[2])
    assert_match(/^cache_write.active_support /, log.last.last)
  end
end
