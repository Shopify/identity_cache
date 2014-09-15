require "test_helper"

class ReadonlyTest < IdentityCache::TestCase
  def setup
    super
    IdentityCache.readonly = true
    @key, @value = 'foo', 'bar'
    @record = Item.new
    @record.id = 1
    @record.title = 'bob'
    @bob = Item.create!(:title => 'bob')
    @joe = Item.create!(:title => 'joe')
    @fred = Item.create!(:title => 'fred')
  end

  def teardown
    IdentityCache.readonly = nil
    super
  end

  def test_write_should_not_update_cache
    assert_memcache_operations(0) do
      fetcher.write(@key, @value)
    end
    assert_nil backend.read(@key)
  end

  def test_delete_should_not_update_cache
    backend.write(@key, @value)
    assert_memcache_operations(0) do
      fetcher.delete(@key)
    end
    assert_equal @value, backend.read(@key)
  end

  def test_clear_should_not_update_cache
    backend.write(@key, @value)
    assert_memcache_operations(0) do
      fetcher.clear
    end
    assert_equal @value, backend.read(@key)
  end

  def test_fetch_should_not_update_cache
    fetch = Spy.on(IdentityCache.cache, :fetch).and_call_through
    Item.expects(:resolve_cache_miss).with(1).once.returns(@record)

    assert_readonly_fetch do
      assert_equal @record, Item.fetch(1)
    end
    assert_nil backend.read(@record.primary_cache_index_key)
    assert fetch.has_been_called_with?(@record.primary_cache_index_key)
  end

  def test_fetch_multi_should_not_update_cache
    fetch_multi = Spy.on(IdentityCache.cache, :fetch_multi).and_call_through

    assert_readonly_fetch_multi do
      assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
    end
    keys = [@bob, @joe, @fred].map(&:primary_cache_index_key)
    assert_empty backend.read_multi(*keys)
    assert fetch_multi.has_been_called_with?(*keys)
  end

  protected

  def assert_readonly_fetch
    cas = Spy.on(backend, :cas).and_call_through
    yield
    assert cas.has_been_called?
  end

  def assert_readonly_fetch_multi
    cas_multi = Spy.on(backend, :cas_multi).and_call_through
    yield
    assert cas_multi.has_been_called?
  end
end

class FallbackReadonlyTest < ReadonlyTest
  def setup
    super
    IdentityCache.cache_backend = @backend = ActiveSupport::Cache::MemoryStore.new
  end

  protected

  def assert_readonly_fetch
    read = Spy.on(backend, :read).and_call_through
    write = Spy.on(backend, :write).and_call_through
    yield
    assert read.has_been_called?
    refute write.has_been_called?
  end

  def assert_readonly_fetch_multi
    read_multi = Spy.on(backend, :read_multi).and_call_through
    write = Spy.on(backend, :write).and_call_through
    yield
    assert read_multi.has_been_called?
    refute write.has_been_called?
  end
end

class ReadonlySnappyPackTest < ReadonlyTest
  def setup
    @snappy_pack = true
    super
  end
end
