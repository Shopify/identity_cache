require "test_helper"

class IdentityCacheTest < IdentityCache::TestCase

  class BadModel < ActiveRecord::Base
  end

  def test_should_use_cache_outside_transaction
    assert_equal true, IdentityCache.should_use_cache?
  end

  def test_should_use_cache_in_transaction
    ActiveRecord::Base.transaction do
      assert_equal false, IdentityCache.should_use_cache?
    end
  end
end
