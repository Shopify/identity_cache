# frozen_string_literal: true
require "test_helper"

class MemoizedCacheProxyTest < IdentityCache::TestCase
  def test_changing_default_cache
    IdentityCache.cache_backend = ActiveSupport::Cache::MemoryStore.new
    IdentityCache.cache.write('foo', 'bar')
    assert_equal('bar', IdentityCache.cache.fetch('foo'))
  end

  def test_fetch_multi_with_fallback_fetcher
    IdentityCache.cache_backend = backend = ActiveSupport::Cache::MemoryStore.new
    IdentityCache.cache.write('foo', 'bar')
    backend.expects(:write).with('bar', 'baz')
    yielded = nil
    assert_equal(
      { 'foo' => 'bar', 'bar' => 'baz' },
      IdentityCache.cache.fetch_multi('foo', 'bar') { |_| yielded = ['baz'] }
    )
    assert_equal(['baz'], yielded)
  end

  def test_fetch_should_short_circuit_on_memoized_values
    fetcher.expects(:fetch).never

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', 'bar')
      assert_equal 'bar', IdentityCache.cache.fetch('foo')
    end
  end

  def test_fetch_should_short_circuit_on_falsy_memoized_values
    fetcher.expects(:fetch).never

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', nil)
      assert_nil IdentityCache.cache.fetch('foo')
      IdentityCache.cache.write('bar', false)
      assert_equal false, IdentityCache.cache.fetch('bar')
    end
  end

  def test_fetch_should_try_memcached_on_not_memoized_values
    fetcher.expects(:fetch).with('foo').returns('bar')

    IdentityCache.cache.with_memoization do
      assert_equal 'bar', IdentityCache.cache.fetch('foo')
    end
  end

  def test_write_should_memoize_values
    fetcher.expects(:fetch).never
    fetcher.expects(:write).with('foo', 'bar')

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', 'bar')
      assert_equal 'bar', IdentityCache.cache.fetch('foo')
    end
  end

  def test_fetch_should_memoize_values
    backend.write('foo', 'bar')

    IdentityCache.cache.with_memoization do
      assert_equal 'bar', IdentityCache.cache.fetch('foo')
      backend.delete('foo')
      assert_equal 'bar', IdentityCache.cache.fetch('foo')
    end
  end

  def test_fetch_multi_should_memoize_values
    expected_hash = { 'foo' => 'bar', 'fooz' => IdentityCache::CACHED_NIL }

    backend.write('foo', 'bar')

    IdentityCache.cache.with_memoization do
      assert_equal(expected_hash, IdentityCache.cache.fetch_multi('foo', 'fooz') { |_| [IdentityCache::CACHED_NIL] })
      assert_equal(expected_hash, IdentityCache.cache.memoized_key_values)
      backend.delete('foo')
      backend.write('fooz', 'baz')
      assert_equal(expected_hash, IdentityCache.cache.fetch_multi('foo', 'fooz'))
    end
  end

  def test_fetch_multi_with_partially_memoized_should_read_missing_keys_from_memcache
    IdentityCache.cache.write('foo', 'bar')
    @backend.write('fooz', 'baz')

    IdentityCache.cache.with_memoization do
      assert_equal({ 'foo' => 'bar', 'fooz' => 'baz' }, IdentityCache.cache.fetch_multi('foo', 'fooz'))
    end
  end

  def test_fetch_multi_with_blank_values_should_not_hit_the_cache_engine
    @backend.expects(:fetch_multi).never

    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', [])
      IdentityCache.cache.write('bar', false)
      IdentityCache.cache.write('baz', {})
      assert_equal({ 'foo' => [], 'bar' => false, 'baz' => {} }, IdentityCache.cache.fetch_multi('foo', 'bar', 'baz'))
    end
  end

  def test_with_memoization_should_not_clear_rails_cache_when_the_block_ends
    IdentityCache.cache.with_memoization do
      IdentityCache.cache.write('foo', 'bar')
    end
    assert_equal('bar', @backend.fetch('foo'))
  end

  def test_write_notifies
    events = 0
    expected = { memoizing: false }
    subscriber = ActiveSupport::Notifications.subscribe('cache_write.identity_cache') do |_, _, _, _, payload|
      events += 1
      assert_equal expected, payload
    end
    IdentityCache.cache.write('foo', 'bar')
    assert_equal(1, events)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_delete_notifies
    events = 0
    expected = { memoizing: false }
    subscriber = ActiveSupport::Notifications.subscribe('cache_delete.identity_cache') do |_, _, _, _, payload|
      events += 1
      assert_equal expected, payload
    end
    IdentityCache.cache.delete('foo')
    assert_equal(1, events)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_clear_notifies
    events = 0
    subscriber = ActiveSupport::Notifications.subscribe('cache_clear.identity_cache') do |_, _, _, _, payload|
      events += 1
      assert payload.empty?
    end
    IdentityCache.cache.clear
    assert_equal(1, events)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
