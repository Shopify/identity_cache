require "test_helper"

class MemoizedCacheProxyTest < IdentityCache::TestCase
  def setup
    super
    IdentityCache.cache_backend = Rails.cache
  end

  def test_changing_default_cache
    IdentityCache.cache_backend = ActiveSupport::Cache::MemoryStore.new
    IdentityCache.cache.write('foo', 'bar')
    assert_equal 'bar', IdentityCache.cache.read('foo')
  end

  def test_read_should_short_circuit_on_memoized_values
    Rails.cache.expects(:read).never

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', 'bar')
      assert_equal 'bar', IdentityCache.cache.read('foo')
    end
  end

  def test_read_should_short_circuit_on_falsy_memoized_values
    Rails.cache.expects(:read).never

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', nil)
      assert_equal nil, IdentityCache.cache.read('foo')
      IdentityCache.cache.write('bar', false)
      assert_equal false, IdentityCache.cache.read('bar')
    end
  end

  def test_read_should_try_memcached_on_not_memoized_values
    Rails.cache.expects(:read).with('foo').returns('bar')

    IdentityCache.cache.with_memoization do
      assert_equal 'bar', IdentityCache.cache.read('foo')
    end
  end

  def test_write_should_memoize_values
    Rails.cache.expects(:read).never
    Rails.cache.expects(:write).with('foo', 'bar')


    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', 'bar')
      assert_equal 'bar', IdentityCache.cache.read('foo')
    end
  end

  def test_read_should_memoize_values
    IdentityCache.cache_backend = backend = ActiveSupport::Cache::MemoryStore.new
    backend.write('foo', 'bar')

    IdentityCache.cache.with_memoization do
      assert_equal 'bar', IdentityCache.cache.read('foo')
      backend.delete('foo')
      assert_equal 'bar', IdentityCache.cache.read('foo')
    end
  end

  def test_read_multi_should_memoize_values
    IdentityCache.cache_backend = backend = ActiveSupport::Cache::MemoryStore.new
    backend.write('foo', 'bar')

    IdentityCache.cache.with_memoization do
      assert_equal({'foo' => 'bar'}, IdentityCache.cache.read_multi('foo', 'fooz'))
      backend.delete('foo')
      backend.write('fooz', 'baz')
      assert_equal({'foo' => 'bar'}, IdentityCache.cache.read_multi('foo', 'fooz'))
    end
  end

  def test_read_multi_with_partially_memoized_should_read_missing_keys_from_memcache
    IdentityCache.cache.write('foo', 'bar')
    Rails.cache.write('fooz', 'baz')

    IdentityCache.cache.with_memoization do
      assert_equal({'foo' => 'bar', 'fooz' => 'baz'}, IdentityCache.cache.read_multi('foo', 'fooz'))
    end
  end

  def test_read_multi_with_blank_values_should_not_hit_the_cache_engine
    Rails.cache.expects(:read_multi).never

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', [])
      IdentityCache.cache.write('bar', false)
      IdentityCache.cache.write('baz', {})
      assert_equal({'foo' => [], 'bar' => false, 'baz' => {}}, IdentityCache.cache.read_multi('foo', 'bar', 'baz'))
    end
  end

  def test_with_memoization_should_not_clear_rails_cache_when_the_block_ends
    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', 'bar')
    end

    assert_equal 'bar', Rails.cache.read('foo')
  end

  def test_batching_deletes
    c = IdentityCache.cache

    c.cache_backend.expects('delete').with('foo').once
    c.cache_backend.expects('delete').with('bar').once

    c.begin_batch
    c.delete('foo')
    c.delete('foo')
    c.delete('bar')
    c.end_batch
  end

  def test_batching_handles_nested_transactions
    c = IdentityCache.cache
    c.cache_backend.expects('delete').with('foo').twice
    c.cache_backend.expects('delete').with('bar').once
    c.cache_backend.expects('delete').with('baz').once

    c.begin_batch
    3.times { c.delete('foo') }
    c.delete('bar')
    c.begin_batch
    4.times { c.delete('foo') }
    c.delete('baz')
    c.end_batch
    c.end_batch
  end

end
