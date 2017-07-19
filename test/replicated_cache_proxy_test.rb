require "test_helper"

class ReplicatedCacheProxyTest < IdentityCache::TestCase
  def setup
    super
    @backend = ActiveSupport::Cache::MemoryStore.new
    @proxy = IdentityCache::ReplicatedCacheProxy.new(@backend, blob_replication_factor: 2)
  end

  def test_write_writes_both_keys
    @proxy.write("k", "tacocat")
    assert_equal("tacocat", @backend.fetch("k:0"))
    assert_equal("tacocat", @backend.fetch("k:1"))
  end

  def test_deletes_both_keys
    @backend.write("k:0", "tacocat")
    @backend.write("k:1", "tacocat")
    @proxy.delete("k")
    assert_nil(@backend.fetch("k:0"))
    assert_nil(@backend.fetch("k:1"))
  end

  def test_fetch_will_return_value_from_one_of_the_keys
    @backend.write("k:0", "tacocat")
    @backend.write("k:1", "tacocat")
    assert_equal("tacocat", @proxy.fetch("k"))
  end

  def test_fetch_multi_will_return_a_mix_of_values
    @backend.write("k:0", "tacocat")
    @backend.write("k:1", "tacocat")
    @backend.write("l:0", "tacodog")
    @backend.write("l:1", "tacodog")
    assert_equal({ "k" => "tacocat", "l" => "tacodog" }, @proxy.fetch_multi("k", "l"))
  end

  def test_clear_clears_the_backend
    @backend.write("k:0", "tacocat")
    @proxy.clear
    assert_nil(@backend.fetch("k:0"))
  end
end
