require "test_helper"

class IdentityCacheTest < IdentityCache::TestCase

  class BadModelBase < ActiveRecord::Base
    include IdentityCache
  end

  class BadModel < BadModelBase
  end

  def test_identity_cache_raises_if_loaded_twice
    assert_raises(IdentityCache::AlreadyIncludedError) do
      BadModel.class_eval do
        include IdentityCache
      end
    end
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
