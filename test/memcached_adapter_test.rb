require 'memcached'
require 'test_helper'

class MemcachedAdapterTest < IdentityCache::TestCase
  KEY = 'foo'

  def setup
    @client = IdentityCache::MemcachedAdapter.new("localhost:#{$memcached_port}")
  end

  def teardown
    @client.delete(KEY)
  end

  def test_get
    value, cas = @client.get(KEY)
    assert_nil value
    assert_nil cas
  end

  def test_add
    value, cas = @client.get(KEY)
    assert_nil value
    assert_nil cas

    @client.add(KEY, 2)
    value, cas = @client.get(KEY)
    assert 2, value

    @client.add(KEY, 99)
    value, cas = @client.get(KEY)
    assert 2, value
  end

  def test_cas
    @client.add(KEY, 1)
    value, cas = @client.get(KEY)
    @client.cas(KEY, 2, cas)
    @client.cas(KEY, 99, cas)
    value, cas = @client.get(KEY)
    assert_equal 2, value
  end

  def test_cas_when_delete
    @client.add(KEY, 1)
    value, cas = @client.get(KEY)
    assert_equal 1, value

    @client.delete(KEY)
    @client.cas(KEY, 1000, cas)
    assert_nil @client.get(KEY)
  end

  def test_cas_when_replace_value
    @client.add(KEY, 1)
    value, cas = @client.get(KEY)
    assert_equal 1, value

    @client.replace(KEY, 2)
    @client.cas(KEY, 1000, cas)
    assert_equal 2, @client.get(KEY)[0]
  end

  def test_replace
    @client.replace(KEY, 99)
    assert [nil, nil], @client.get(KEY)

    @client.add(KEY, 1)
    @client.replace(KEY, 99)
    value, cas = @client.get(KEY)
    assert_equal 99, value
  end
end
