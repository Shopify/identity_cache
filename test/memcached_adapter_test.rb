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

  def test_replace
    @client.replace(KEY, 99, 0)
    assert [nil, nil], @client.get(KEY)

    @client.add(KEY, 1)
    @client.replace(KEY, 99, 0)
    value, cas = @client.get(KEY)
    assert_equal 99, value
  end
end
