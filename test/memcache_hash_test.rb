require 'test_helper'

class MemcacheHashTest < IdentityCache::TestCase
  def test_cityhash
    test_hash_fn(:_cityhash_memcache_hash)
  end

  def test_digest_md5
    test_hash_fn(:_digest_md5_memcache_hash)
  end

private

  ## Ensure that our hash functions accept a string and return a uint64.
  def test_hash_fn(method_name)
    prng = Random.new(Time.now.to_i)
    20.times do
      random_str = Array.new(200){rand(36).to_s(36)}.join
      hash_val = IdentityCache.send(method_name, random_str)
      assert hash_val
      assert_kind_of Numeric, hash_val
      assert_equal 0, (hash_val >> 64)
    end
  end
end
