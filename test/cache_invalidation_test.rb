require "test_helper"

class CacheInvalidationTest < IdentityCache::TestCase
  def setup
    super

    @record = Item.new(:title => 'foo')
    @record.associated_records << AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.save
    @record.reload
    @baz, @bar = @record.associated_records[0], @record.associated_records[1]
  end

  def test_reload_invalidate_cached_ids
    Item.cache_has_many :associated_records, :embed => :ids

    variable_name = "@#{@record.class.send(:embedded_associations)[:associated_records][:ids_variable_name]}"

    @record.fetch_associated_record_ids
    assert_equal [@baz.id, @bar.id], @record.instance_variable_get(variable_name)

    @record.reload
    assert_equal nil, @record.instance_variable_get(variable_name)

    @record.fetch_associated_record_ids
    assert_equal [@baz.id, @bar.id], @record.instance_variable_get(variable_name)
  end

  def test_reload_invalidate_cached_objects
    Item.cache_has_many :associated_records, :embed => :ids

    variable_name = "@#{@record.class.send(:embedded_associations)[:associated_records][:records_variable_name]}"

    @record.fetch_associated_records
    assert_equal [@baz, @bar], @record.instance_variable_get(variable_name)

    @record.reload
    assert_equal nil, @record.instance_variable_get(variable_name)

    @record.fetch_associated_records
    assert_equal [@baz, @bar], @record.instance_variable_get(variable_name)
  end

  def test_after_a_reload_the_cache_perform_as_expected
    Item.cache_has_many :associated_records, :embed => :ids

    assert_equal [@baz, @bar], @record.associated_records
    assert_equal [@baz, @bar], @record.fetch_associated_records

    @baz.destroy
    @record.reload

    assert_equal [@bar], @record.associated_records
    assert_equal [@bar], @record.fetch_associated_records
  end

  def test_cache_invalidation_expire_properly_if_child_is_embed_in_multiple_parents
    Item.cache_has_many :associated_records, :embed => true
    ItemTwo.cache_has_many :associated_records, :embed => true

    baz = AssociatedRecord.new(:name => 'baz')

    record1 = Item.new(:title => 'foo')
    record1.associated_records << baz
    record1.save!

    record2 = ItemTwo.new(:title => 'bar')
    record2.associated_records << baz
    record2.save!

    record1.class.fetch(record1.id)
    record2.class.fetch(record2.id)

    expected_keys = [
      record1.primary_cache_index_key,
      record2.primary_cache_index_key,
    ]

    expected_keys.each do |expected_key|
      assert IdentityCache.cache.fetch(expected_key) { nil }
    end

    baz.save!

    expected_keys.each do |expected_key|
      refute IdentityCache.cache.fetch(expected_key) { nil }
    end
  end

  def test_cache_invalidation_expire_properly_if_child_is_embed_in_multiple_parents_with_ids
    Item.cache_has_many :associated_records, :embed => :ids
    ItemTwo.cache_has_many :associated_records, :embed => :ids

    baz = AssociatedRecord.new(:name => 'baz')

    record1 = Item.new(:title => 'foo')
    record1.save

    record2 = ItemTwo.new(:title => 'bar')
    record2.save

    record1.class.fetch(record1.id)
    record2.class.fetch(record2.id)

    expected_keys = [
      record1.primary_cache_index_key,
      record2.primary_cache_index_key,
    ]

    expected_keys.each do |expected_key|
      assert IdentityCache.cache.fetch(expected_key) { nil }
    end

    baz.item = record1
    baz.item_two = record2
    baz.save!

    expected_keys.each do |expected_key|
      refute IdentityCache.cache.fetch(expected_key) { nil }
    end
  end
end
