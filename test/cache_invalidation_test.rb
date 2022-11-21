# frozen_string_literal: true

require "test_helper"

class CacheInvalidationTest < IdentityCache::TestCase
  def setup
    super

    @record = Item.new(title: "foo")
    @record.associated_records << AssociatedRecord.new(name: "bar")
    @record.associated_records << AssociatedRecord.new(name: "baz")
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

    baz = AssociatedRecord.new(name: "baz")

    record1 = Item.new(title: "foo")
    record1.associated_records << baz
    record1.save!

    record2 = ItemTwo.new(title: "bar")
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

    baz = AssociatedRecord.new(name: "baz")

    record1 = Item.new(title: "foo")
    record1.save

    record2 = ItemTwo.new(title: "bar")
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
    record = Item.create(title: "foo")
    record.class.fetch(record.id)

    refute_nil(IdentityCache.cache.fetch(record.primary_cache_index_key) { nil })

    Item.expire_primary_key_cache_index(record.id)

    assert_nil(IdentityCache.cache.fetch(record.primary_cache_index_key) { nil })
  end

  def test_dedup_cache_invalidation_of_records_embedded_twice_through_different_associations
    Item.cache_has_many(:associated_records, embed: true)
    AssociatedRecord.cache_has_many(:deeply_associated_records, embed: true)
    Item.cache_has_many(:deeply_associated_records, embed: true)

    deeply_associated_record = DeeplyAssociatedRecord.new(name: "deep", item_id: @record.id)
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
        @record.update!(title: "foo2")
      end
    end
    assert_equal([:sql, :sql, :sql, :cache], log.map(&:first))
    sql_queries = log.first(3).map(&:last)
    assert_match(/^BEGIN\b/, sql_queries[0])
    assert_match(/^UPDATE\b/, sql_queries[1])
    assert_match(/^COMMIT\b/, sql_queries[2])
    assert_match(/^cache_write.active_support /, log.last.last)
  end

  def test_expire_cache_with_primary_key_only
    assert_equal(@record, Item.fetch(1))
    refute_equal(IdentityCache::DELETED, read_entity)
    assert(@record.expire_cache)
    assert_equal(IdentityCache::DELETED, read_entity)
  end

  def test_expire_cache_with_primary_key_only_on_failure
    assert_equal(@record, Item.fetch(1))
    refute_equal(IdentityCache::DELETED, read_entity)

    with_cache_backend do
      refute(@record.expire_cache)
    end

    refute_equal(IdentityCache::DELETED, read_entity)
  end

  def test_expire_cache_with_extra_indexes
    Item.cache_index(:id, :title, unique: true)
    Item.cache_index(:title, unique: true)

    assert_equal(@record, Item.fetch(@record.id))
    assert_equal(@record, Item.fetch_by_title(@record.title))
    assert_equal(@record, Item.fetch_by_id_and_title(@record.id, @record.title))
    assert_equal(@record.id, read_by_title)
    assert_equal(@record.id, read_by_id_and_title)

    assert(@record.expire_cache)

    assert_equal(IdentityCache::DELETED, read_entity)
    assert_equal(IdentityCache::DELETED, read_by_title)
    assert_equal(IdentityCache::DELETED, read_by_id_and_title)
  end

  def test_expire_cache_with_extra_indexes_on_failure
    Item.cache_index(:id, :title, unique: true)
    Item.cache_index(:title, unique: true)

    assert_equal(@record, Item.fetch(@record.id))
    assert_equal(@record, Item.fetch_by_title(@record.title))
    assert_equal(@record, Item.fetch_by_id_and_title(@record.id, @record.title))
    assert_equal(@record.id, read_by_title)
    assert_equal(@record.id, read_by_id_and_title)

    with_cache_backend do
      refute(@record.expire_cache)
    end

    refute_equal(IdentityCache::DELETED, read_entity)
    refute_equal(IdentityCache::DELETED, read_by_title)
    refute_equal(IdentityCache::DELETED, read_by_id_and_title)
  end

  # simulate a single failure for expire_cache to see if everything
  # behaves as expected regarding response of `expire_cache`, keep
  # both tests: the integration with real connection issue and mocked
  # one to be more thorough.
  def test_expire_cache_with_extra_indexes_on_single_failure
    Item.cache_index(:id, :title, unique: true)
    Item.cache_index(:title, unique: true)

    mocked_backend = MockedCacheBackend.new(backend)
    mocked_backend.stub_call(":attr:Item:id:id/title:", IdentityCache::DELETED)

    with_cache_backend(mocked_backend) do
      assert_equal(@record, Item.fetch(@record.id))
      assert_equal(@record, Item.fetch_by_title(@record.title))
      assert_equal(@record, Item.fetch_by_id_and_title(@record.id, @record.title))
      assert_equal(@record.id, read_by_title)
      assert_equal(@record.id, read_by_id_and_title)

      refute(@record.expire_cache)

      assert_equal(IdentityCache::DELETED, read_entity)
      assert_equal(IdentityCache::DELETED, read_by_title)
      refute_equal(IdentityCache::DELETED, read_by_id_and_title)
    end
  end

  def test_expire_cache_through_association
    Item.cache_has_many(:associated_records, embed: true)

    # setup cache
    Item.fetch(1)
    [@baz, @bar].each { |ar| AssociatedRecord.fetch(ar.id) }

    refute_equal(IdentityCache::DELETED, read_entity)
    refute_equal(IdentityCache::DELETED, read_entity(@baz))
    refute_equal(IdentityCache::DELETED, read_entity(@bar))

    assert(@bar.expire_cache)

    assert_equal(IdentityCache::DELETED, read_entity)
    assert_equal(IdentityCache::DELETED, read_entity(@bar))
    refute_equal(IdentityCache::DELETED, read_entity(@baz))
  end

  def test_expire_cache_through_association_on_failure
    Item.cache_has_many(:associated_records, embed: true)

    # setup cache
    Item.fetch(1)
    [@baz, @bar].each { |ar| AssociatedRecord.fetch(ar.id) }

    refute_equal(IdentityCache::DELETED, read_entity)
    refute_equal(IdentityCache::DELETED, read_entity(@baz))
    refute_equal(IdentityCache::DELETED, read_entity(@bar))

    with_cache_backend do
      refute(@bar.expire_cache)
    end

    refute_equal(IdentityCache::DELETED, read_entity)
    refute_equal(IdentityCache::DELETED, read_entity(@bar))
    refute_equal(IdentityCache::DELETED, read_entity(@baz))
  end

  def test_expire_cache_through_association_on_single_failure
    Item.cache_has_many(:associated_records, embed: true)

    mocked_backend = MockedCacheBackend.new(backend)
    mocked_backend.stub_call(":blob:Item:", IdentityCache::DELETED)

    with_cache_backend(mocked_backend) do
      # setup cache
      Item.fetch(1)
      [@baz, @bar].each { |ar| AssociatedRecord.fetch(ar.id) }

      refute_equal(IdentityCache::DELETED, read_entity)
      refute_equal(IdentityCache::DELETED, read_entity(@baz))
      refute_equal(IdentityCache::DELETED, read_entity(@bar))

      refute(@bar.expire_cache)

      refute_equal(IdentityCache::DELETED, read_entity)
      assert_equal(IdentityCache::DELETED, read_entity(@bar))
      refute_equal(IdentityCache::DELETED, read_entity(@baz))
    end
  end

  private

  def read_entity(entity = @record)
    backend.read(entity.primary_cache_index_key)
  end

  def read_by_id_and_title
    backend.read(@record.cache_indexes.first.cache_key([@record.id, @record.title]))
  end

  def read_by_title
    backend.read(@record.cache_indexes.last.cache_key(@record.title))
  end

  def with_cache_backend(tmp_backend = CacheConnection.unconnected_cache_backend)
    IdentityCache.cache_backend = tmp_backend
    yield
  ensure
    IdentityCache.cache_backend = backend
  end
end
