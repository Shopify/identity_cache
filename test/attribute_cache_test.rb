require "test_helper"

class AttributeCacheTest < IdentityCache::TestCase
  def setup
    super
    AssociatedRecord.cache_attribute :name
    AssociatedRecord.cache_attribute :record, :by => [:id, :name]

    @parent = Record.create!(:title => 'bob')
    @record = @parent.associated_records.create!(:name => 'foo')
    @name_attribute_key = "IDC:attribute:AssociatedRecord:name:id:#{cache_hash(@record.id.to_s)}"
    @blob_key = "IDC:blob:AssociatedRecord:#{cache_hash("id:integer,name:string,record_id:integer")}:1"
  end

  def test_attribute_values_are_returned_on_cache_hits
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns('foo')
    assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
  end

  def test_attribute_values_are_fetched_and_returned_on_cache_misses
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns(nil)
    Record.connection.expects(:select_value).with("SELECT #{safe_column_name("name")} FROM #{safe_table_name("associated_records")} WHERE #{safe_column_name("id")} = 1 LIMIT 1").returns('foo')
    assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
  end

  def test_attribute_values_are_stored_in_the_cache_on_cache_misses

    # Cache miss, so
    IdentityCache.cache.expects(:read).with(@name_attribute_key).returns(nil)

    # Grab the value of the attribute from the DB
    Record.connection.expects(:select_value).with("SELECT #{safe_column_name("name")} FROM #{safe_table_name("associated_records")} WHERE #{safe_column_name("id")} = 1 LIMIT 1").returns('foo')

    # And write it back to the cache
    IdentityCache.cache.expects(:write).with(@name_attribute_key, 'foo').returns(nil)

    assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_is_saved
    IdentityCache.cache.expects(:delete).with(@name_attribute_key)
    IdentityCache.cache.expects(:delete).with(@blob_key)
    @record.save!
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_with_changed_attributes_is_saved
    IdentityCache.cache.expects(:delete).with(@name_attribute_key)
    IdentityCache.cache.expects(:delete).with(@blob_key)
    @record.name = 'bar'
    @record.save!
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_an_existing_record_is_destroyed
    IdentityCache.cache.expects(:delete).with(@name_attribute_key)
    IdentityCache.cache.expects(:delete).with(@blob_key)
    @record.destroy
  end

  def test_cached_attribute_values_are_expired_from_the_cache_when_a_new_record_is_saved
    IdentityCache.cache.expects(:delete).with("IDC:blob:AssociatedRecord:#{cache_hash("id:integer,name:string,record_id:integer")}:2")
    @parent.associated_records.create(:name => 'bar')
  end

  def test_fetching_by_attribute_delegates_to_block_if_transactions_are_open
    IdentityCache.cache.expects(:read).with(@name_attribute_key).never

    Record.connection.expects(:select_value).with("SELECT #{safe_column_name("name")} FROM #{safe_table_name("associated_records")} WHERE #{safe_column_name("id")} = 1 LIMIT 1").returns('foo')

    @record.transaction do
      assert_equal 'foo', AssociatedRecord.fetch_name_by_id(1)
    end
  end
end
