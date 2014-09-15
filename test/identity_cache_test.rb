require "test_helper"

class IdentityCacheTest < IdentityCache::TestCase

  class BadModel < ActiveRecord::Base
  end

  def test_identity_cache_raises_if_loaded_twice
    assert_raises(IdentityCache::AlreadyIncludedError) do
      BadModel.class_eval do
        include IdentityCache
        include IdentityCache
      end
    end
  end

end

class IdentityCacheSnappyPackTest < IdentityCacheTest
  def setup
    @snappy_pack = true
    super
  end
end 
