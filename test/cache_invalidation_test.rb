require "test_helper"

class CacheInvalidationTest < IdentityCache::TestCase
  def setup
    super
    Item.cache_has_many :associated_records, :embed => :ids

    @record = Item.new(:title => 'foo')
    @record.associated_records << AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.save
    @record.reload
    @baz, @bar = @record.associated_records[0], @record.associated_records[1]
  end

  def test_reload_invalidate_cached_ids
    variable_name = "@#{@record.class.send(:embedded_associations)[:associated_records][:ids_variable_name]}"

    @record.fetch_associated_record_ids
    assert_equal [@baz.id, @bar.id], @record.instance_variable_get(variable_name)

    @record.reload
    assert_equal nil, @record.instance_variable_get(variable_name)

    @record.fetch_associated_record_ids
    assert_equal [@baz.id, @bar.id], @record.instance_variable_get(variable_name)
  end

  def test_reload_invalidate_cached_objects
    variable_name = "@#{@record.class.send(:embedded_associations)[:associated_records][:records_variable_name]}"

    @record.fetch_associated_records
    assert_equal [@baz, @bar], @record.instance_variable_get(variable_name)

    @record.reload
    assert_equal nil, @record.instance_variable_get(variable_name)

    @record.fetch_associated_records
    assert_equal [@baz, @bar], @record.instance_variable_get(variable_name)
  end

  def test_after_a_reload_the_cache_perform_as_expected
    assert_equal [@baz, @bar], @record.associated_records
    assert_equal [@baz, @bar], @record.fetch_associated_records

    @baz.destroy
    @record.reload

    assert_equal [@bar], @record.associated_records
    assert_equal [@bar], @record.fetch_associated_records
  end
end

class CacheInvalidationSnappyPackTest < CacheInvalidationTest
  include IdentityCache::SnappyPackTestCase
end

