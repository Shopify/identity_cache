require "test_helper"

class FetchTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    Item.cache_index :title, :unique => true
    Item.cache_index :id, :title, :unique => true

    @record = Item.new
    @record.id = 1
    @record.title = 'bob'
    @cached_value = {:class => @record.class}
    @record.encode_with(@cached_value)
    @blob_key = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:1"
    @index_key = "#{NAMESPACE}index:Item:title:#{cache_hash('bob')}"
  end

  def test_fetch_cache_hit
    IdentityCache.cache.expects(:read).with(@blob_key).returns(@cached_value)

    assert_equal @record, Item.fetch(1)
  end

  def test_fetch_hit_cache_namespace
    old_ns = IdentityCache.cache_namespace
    IdentityCache.cache_namespace = proc { |model| "#{model.table_name}:#{old_ns}" }

    new_blob_key = "items:#{@blob_key}"
    IdentityCache.cache.expects(:read).with(new_blob_key).returns(@cached_value)

    assert_equal @record, Item.fetch(1)
  ensure
    IdentityCache.cache_namespace = old_ns
  end

  def test_exists_with_identity_cache_when_cache_hit
    IdentityCache.cache.expects(:read).with(@blob_key).returns(@cached_value)

    assert Item.exists_with_identity_cache?(1)
  end

  def test_exists_with_identity_cache_when_cache_miss_and_in_db
    IdentityCache.cache.expects(:read).with(@blob_key).returns(nil)
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)

    assert Item.exists_with_identity_cache?(1)
  end

  def test_exists_with_identity_cache_when_cache_miss_and_not_in_db
    IdentityCache.cache.expects(:read).with(@blob_key).returns(nil)
    Item.expects(:resolve_cache_miss).with(1).once.returns(nil)

    assert !Item.exists_with_identity_cache?(1)
  end

  def test_fetch_miss
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)

    IdentityCache.cache.expects(:read).with(@blob_key).returns(nil)
    IdentityCache.cache.expects(:write).with(@blob_key, @cached_value)

    assert_equal @record, Item.fetch(1)
  end

  def test_fetch_by_id_not_found_should_return_nil
    nonexistent_record_id = 10
    IdentityCache.cache.expects(:write).with(@blob_key + '0', IdentityCache::CACHED_NIL)

    assert_equal nil, Item.fetch_by_id(nonexistent_record_id)
  end

  def test_fetch_not_found_should_raise
    nonexistent_record_id = 10
    IdentityCache.cache.expects(:write).with(@blob_key + '0', IdentityCache::CACHED_NIL)

    assert_raises(ActiveRecord::RecordNotFound) { Item.fetch(nonexistent_record_id) }
  end

  def test_cached_nil_expiry_on_record_creation
    key = @record.primary_cache_index_key

    assert_equal nil, Item.fetch_by_id(@record.id)
    assert_equal IdentityCache::CACHED_NIL, IdentityCache.cache.read(key)

    @record.save!
    assert_nil IdentityCache.cache.read(key)
  end

  def test_fetch_by_title_hit
    # Read record with title bob
    IdentityCache.cache.expects(:read).with(@index_key).returns(nil)

    # - not found, use sql, SELECT id FROM records WHERE title = '...' LIMIT 1"
    Item.connection.expects(:select_value).returns(1)

    # cache sql result
    IdentityCache.cache.expects(:write).with(@index_key, 1)

    # got id, do memcache lookup on that, hit -> done
    IdentityCache.cache.expects(:read).with(@blob_key).returns(@cached_value)

    assert_equal @record, Item.fetch_by_title('bob')
  end

  def test_fetch_by_title_cache_namespace
    Item.send(:include, SwitchNamespace)
    IdentityCache.cache.expects(:read).with("ns:#{@index_key}").returns(1)
    IdentityCache.cache.expects(:read).with("ns:#{@blob_key}").returns(@cached_value)

    assert_equal @record, Item.fetch_by_title('bob')
  end

  def test_fetch_by_title_stores_idcnil
    Item.connection.expects(:select_value).once.returns(nil)
    Rails.cache.expects(:write).with(@index_key, IdentityCache::CACHED_NIL)
    Rails.cache.expects(:read).with(@index_key).times(3).returns(nil, IdentityCache::CACHED_NIL, IdentityCache::CACHED_NIL)
    assert_equal nil, Item.fetch_by_title('bob') # select_value => nil

    assert_equal nil, Item.fetch_by_title('bob') # returns cached nil
    assert_equal nil, Item.fetch_by_title('bob') # returns cached nil
  end

  def test_fetch_by_bang_method
    Item.connection.expects(:select_value).returns(nil)
    assert_raises ActiveRecord::RecordNotFound do
      Item.fetch_by_title!('bob')
    end
  end
end
