require 'test_helper'

class MemcacheHashTest < IdentityCache::TestCase

  def test_memcache_hash

    prng = Random.new(Time.now.to_i)
    3.times do
      random_str = Array.new(200){rand(36).to_s(36)}.join
      hash_val = IdentityCache.memcache_hash(random_str)
      assert hash_val
      assert_kind_of Numeric, hash_val
      assert_equal 0, (hash_val >> 64)
    end
  end

end
