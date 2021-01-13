# frozen_string_literal: true

require "test_helper"
require "socket"

class CacheFetcherTest < IdentityCache::TestCase
  attr_reader :key, :cache_fetcher

  def setup
    super
    @cache_fetcher = IdentityCache::CacheFetcher.new(backend)
    @key = "key"
  end

  def test_fetch_without_lock_miss
    assert_memcache_operations(2) do # get, add
      assert_equal(:fill_data, cache_fetcher.fetch(key) { :fill_data })
    end
    assert_equal(:fill_data, backend.read(key))
  end

  def test_fetch_miss
    assert_memcache_operations(3) do # get (miss), add (lock), get+cas (fill)
      assert_equal(:fill_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { :fill_data })
    end
    assert_equal(:fill_data, backend.read(key))
  end

  def test_fetch_hit
    cache_fetcher.fetch(key) { :hit_data }
    assert_memcache_operations(1) do # get
      assert_equal(:hit_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { flunk("unexpected yield") })
    end
  end

  def test_fetch_lock_wait
    other_client_takes_lock

    # fill during lock wait
    other_client_operations = 1
    cache_fetcher.expects(:sleep).with do |duration|
      assert_memcache_operations(other_client_operations) do # get+cas
        other_cache_fetcher.fetch(key) { :fill_data }
      end
      duration == 0.9
    end

    assert_memcache_operations(2 + other_client_operations) do # get (miss), get (hit)
      assert_equal(:fill_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { flunk("unexpected yield") })
    end
  end

  def test_fetch_lock_wait_timeout
    other_client_takes_lock

    cache_fetcher.expects(:sleep).with(0.9)
    assert_memcache_operations(3) do # get (miss), get+cas (miss, take lock), get+cas (fill)
      assert_equal(:fill_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { :fill_data })
    end
    assert_equal(:fill_data, backend.read(key))
  end

  def test_fetch_lock_wait_with_cache_invalidation
    other_client_takes_lock

    # invalidate during lock wait
    other_client_operations = 1
    cache_fetcher.expects(:sleep).with do |duration|
      assert_memcache_operations(other_client_operations) do
        other_cache_fetcher.delete(key)
      end
      duration == 0.9
    end

    assert_memcache_operations(3 + other_client_operations) do # get (miss), get (invalidated), get+cas (fallback key)
      assert_equal(:fill_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { :fill_data })
    end
    assert_equal(IdentityCache::DELETED, backend.read(key))
  end

  def test_fetch_lock_wait_with_cache_invalidation_and_relock
    second_client = other_cache_fetcher
    third_client = IdentityCache::CacheFetcher.new(backend)

    second_client_fiber = Fiber.new do
      second_client.fetch(key, fill_lock_duration: 0.9) do
        Fiber.yield
        :second_client_data
      end
    end
    second_client_fiber.resume

    # invalidate during lock wait
    other_client_operations = 4
    cache_fetcher.expects(:sleep).with do |duration|
      assert_memcache_operations(other_client_operations) do
        third_client.delete(key)
        other_client_takes_lock(third_client) # get+cas
        second_client_fiber.resume # get (new lock), get+cas (fallback key)
      end
      duration == 0.9
    end

    assert_memcache_operations(3 + other_client_operations) do # get (other lock), get (new lock), get (fallback key)
      assert_equal(:second_client_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { flunk("unexpected yield") })
    end
    key_value = backend.read(key)
    assert_equal([:fill_locked, third_client.send(:client_id)], key_value.first(2))
  end

  def test_fetch_lock_wait_limit_reached
    data_version = SecureRandom.uuid
    lock = write_lock(data_version: data_version)
    other_client_operations = 3
    cache_fetcher.expects(:sleep).times(3).with do |duration|
      lock = write_lock(data_version: data_version)
      duration == 0.9
    end
    assert_memcache_operations(4 + other_client_operations) do # get (miss) * 4
      assert_raises(IdentityCache::LockWaitTimeout) do
        cache_fetcher.fetch(key, fill_lock_duration: 0.9, lock_wait_limit: 3)
      end
    end
    assert_equal(lock, backend.read(key))
  end

  def test_fetch_lock_attempt_interrupted_with_cache_invalidation
    cache_fetcher.expects(:sleep).never
    backend.expects(:cas).returns(false).with do |got_key|
      other_cache_fetcher.delete(key)
      key == got_key
    end
    other_client_operations = 1
    assert_memcache_operations(2 + other_client_operations) do # add (lock), get (lock), excludes mocked cas
      assert_equal(:fill_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { :fill_data })
    end
    assert_equal(IdentityCache::DELETED, backend.read(key))
  end

  def test_fetch_with_memcached_down
    cache_fetcher = IdentityCache::CacheFetcher.new(unconnected_cache_backend)
    cache_fetcher.expects(:sleep).never
    # 3 operations because the underlying cache store doesn't distinguish between
    # request failures and error responses (e.g. NOT_FOUND or NOT_STORED)
    assert_memcache_operations(3) do # get (miss), add (lock), get (read lock)
      assert_equal(:miss_data, cache_fetcher.fetch(key, fill_lock_duration: 0.9) { :miss_data })
    end
  end

  def test_fetch_with_database_down
    IdentityCache::CacheFetcher.any_instance.expects(:sleep).never
    exc = assert_raises(RuntimeError) do
      other_cache_fetcher.fetch(key, fill_lock_duration: 0.9) { raise 'database down' }
    end
    assert_equal('database down', exc.message)
    exc = assert_raises(RuntimeError) do
      cache_fetcher.fetch(key, fill_lock_duration: 0.9) { raise 'database still down' }
    end
    assert_equal('database still down', exc.message)
  end

  private

  def write_lock(client_id: SecureRandom.uuid, data_version:)
    lock = IdentityCache::CacheFetcher::FillLock.new(client_id: client_id, data_version: data_version)
    other_cache_fetcher.write(key, lock)
    lock
  end

  def other_client_takes_lock(cache_fetcher = other_cache_fetcher)
    cache_fetcher.fetch(key, fill_lock_duration: 0.9) do
      break # skip filling
    end
  end

  def other_cache_fetcher
    @other_cache_fetcher ||= IdentityCache::CacheFetcher.new(backend)
  end

  def unconnected_cache_backend
    CacheConnection.build_backend(address: "127.0.0.1:#{open_port}").tap do |backend|
      backend.extend(IdentityCache::MemCacheStoreCAS) if backend.is_a?(ActiveSupport::Cache::MemCacheStore)
    end
  end

  def open_port
    socket = Socket.new(:INET, :STREAM)
    socket.bind(Addrinfo.tcp('127.0.0.1', 0))
    socket.local_address.ip_port
  ensure
    socket&.close
  end
end
