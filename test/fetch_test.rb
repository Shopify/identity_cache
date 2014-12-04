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

  def test_fetch_with_garbage_input
    Item.connection.expects(:exec_query)
      .with(Item.where(id: 0).limit(1).to_sql, any_parameters)
      .returns(ActiveRecord::Result.new([], []))

    assert_equal nil, Item.fetch_by_id('garbage')
  end

  def test_fetch_cache_hit
    IdentityCache.cache.expects(:fetch).with(@blob_key).returns(@cached_value)

    assert_equal @record, Item.fetch(1)
  end

  def test_fetch_hit_cache_namespace
    old_ns = IdentityCache.cache_namespace
    IdentityCache.cache_namespace = proc { |model| "#{model.table_name}:#{old_ns}" }

    new_blob_key = "items:#{@blob_key}"
    IdentityCache.cache.expects(:fetch).with(new_blob_key).returns(@cached_value)

    assert_equal @record, Item.fetch(1)
  ensure
    IdentityCache.cache_namespace = old_ns
  end

  def test_exists_with_identity_cache_when_cache_hit
    IdentityCache.cache.expects(:fetch).with(@blob_key).returns(@cached_value)

    assert Item.exists_with_identity_cache?(1)
  end

  def test_exists_with_identity_cache_when_cache_miss_and_in_db
    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)

    assert Item.exists_with_identity_cache?(1)
    assert fetch.has_been_called_with?(@blob_key)
  end

  def test_exists_with_identity_cache_when_cache_miss_and_not_in_db
    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through
    Item.expects(:resolve_cache_miss).with(1).once.returns(nil)

    assert !Item.exists_with_identity_cache?(1)
    assert fetch.has_been_called_with?(@blob_key)
  end

  def test_fetch_miss
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)

    results = []
    fetch = Spy.on(IdentityCache.cache, :fetch).and_return {|_, &block| block.call.tap {|result| results << result}}

    assert_equal @record, Item.fetch(1)
    assert fetch.has_been_called_with?(@blob_key)
    assert_equal [@cached_value], results
  end

  def test_fetch_miss_with_non_id_primary_key
    hashed_key = Zlib::crc32("foo") % (2 ** 30 - 1)
    fixture = KeyedRecord.create!(:value => "foo") { |r| r.hashed_key = hashed_key }
    assert_equal fixture, KeyedRecord.fetch(hashed_key)
  end

  def test_fetch_conflict
    resolve_cache_miss = Spy.on(Item, :resolve_cache_miss).and_return do
      @record.send(:expire_cache)
      @record
    end
    add = Spy.on(fetcher, :add).and_call_through

    assert_equal @record, Item.fetch(1)
    assert resolve_cache_miss.has_been_called_with?(1)
    assert add.has_been_called_with?(@blob_key, @cached_value)
    assert_equal IdentityCache::DELETED, backend.read(@record.primary_cache_index_key)
  end

  def test_fetch_conflict_after_delete
    @record.send(:expire_cache)
    assert_equal IdentityCache::DELETED, backend.read(@record.primary_cache_index_key)

    resolve_cache_miss = Spy.on(Item, :resolve_cache_miss).and_return do
      @record.send(:expire_cache)
      @record
    end
    add = Spy.on(IdentityCache.cache.cache_fetcher, :add).and_call_through

    assert_equal @record, Item.fetch(1)
    assert resolve_cache_miss.has_been_called_with?(1)
    refute add.has_been_called?
    assert_equal IdentityCache::DELETED, backend.read(@record.primary_cache_index_key)
  end

  def test_fetch_by_id_not_found_should_return_nil
    nonexistent_record_id = 10
    fetcher.expects(:add).with(@blob_key + '0', IdentityCache::CACHED_NIL)

    assert_equal nil, Item.fetch_by_id(nonexistent_record_id)
  end

  def test_fetch_not_found_should_raise
    nonexistent_record_id = 10
    fetcher.expects(:add).with(@blob_key + '0', IdentityCache::CACHED_NIL)

    assert_raises(ActiveRecord::RecordNotFound) { Item.fetch(nonexistent_record_id) }
  end

  def test_cached_nil_expiry_on_record_creation
    key = @record.primary_cache_index_key

    assert_equal nil, Item.fetch_by_id(@record.id)
    assert_equal IdentityCache::CACHED_NIL, backend.read(key)

    @record.save!
    assert_equal IdentityCache::DELETED, backend.read(key)
  end

  def test_fetch_by_title_hit
    values = []
    fetch = Spy.on(IdentityCache.cache, :fetch).and_return do |key, &block|
      case key
      # Read record with title bob
      when @index_key then block.call.tap {|val| values << val}
      # got id, do memcache lookup on that, hit -> done
      when @blob_key then @cached_value
      end
    end

    # Id not found, use sql, SELECT id FROM records WHERE title = '...' LIMIT 1"
    Item.connection.expects(:exec_query).returns(ActiveRecord::Result.new(['id'], [[1]]))

    assert_equal @record, Item.fetch_by_title('bob')
    assert_equal [1], values
    assert fetch.has_been_called_with?(@index_key)
    assert fetch.has_been_called_with?(@blob_key)
  end

  def test_fetch_by_title_cache_namespace
    Item.send(:include, SwitchNamespace)
    IdentityCache.cache.expects(:fetch).with("ns:#{@index_key}").returns(1)
    IdentityCache.cache.expects(:fetch).with("ns:#{@blob_key}").returns(@cached_value)

    assert_equal @record, Item.fetch_by_title('bob')
  end

  def test_fetch_by_title_stores_idcnil
    Item.connection.expects(:exec_query).once.returns(ActiveRecord::Result.new([], []))
    add = Spy.on(fetcher, :add).and_call_through
    fetch = Spy.on(fetcher, :fetch).and_call_through
    assert_equal nil, Item.fetch_by_title('bob') # exec_query => nil

    assert_equal nil, Item.fetch_by_title('bob') # returns cached nil
    assert_equal nil, Item.fetch_by_title('bob') # returns cached nil

    assert add.has_been_called_with?(@index_key, IdentityCache::CACHED_NIL)
    assert_equal 3, fetch.calls.length
  end

  def test_fetch_by_bang_method
    Item.connection.expects(:exec_query).returns(ActiveRecord::Result.new([], []))
    assert_raises ActiveRecord::RecordNotFound do
      Item.fetch_by_title!('bob')
    end
  end

  def test_fetch_does_not_communicate_to_cache_with_nil_id
    fetcher.expects(:fetch).never
    fetcher.expects(:add).never
    assert_raises(ActiveRecord::RecordNotFound) { Item.fetch(nil) }
  end

  def test_fetch_cache_hit_does_not_checkout_database_connection
    @record.save!
    record = Item.fetch(@record.id)

    ActiveRecord::Base.clear_active_connections!

    assert_equal record, Item.fetch(@record.id)

    assert_equal false, ActiveRecord::Base.connection_handler.active_connections?
  end
end
