require "test_helper"

class IdentityCacheTest < IdentityCache::TestCase

  class BadModel < ActiveRecord::Base
  end

  class ModelWithConnection < ActiveRecord::Base
    establish_connection ActiveRecord::Base.connection_config
  end

  def test_identity_cache_raises_if_loaded_twice
    assert_raises(IdentityCache::AlreadyIncludedError) do
      BadModel.class_eval do
        include IdentityCache
        include IdentityCache
      end
    end
  end

  def test_should_use_cache_inside_transaction_on_specific_model
    ModelWithConnection.transaction do
      assert_equal false, IdentityCache.should_use_cache?
    end
  end
end

class IdentityCacheWithTransactionalFixturesTest < ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  if respond_to?(:use_transactional_tests)
    self.use_transactional_tests = true
  else
    self.use_transactional_fixtures = true
  end
  self.test_order = :random

  def test_should_use_cache_outside_transaction
    assert_equal true, IdentityCache.should_use_cache?
  end

  def test_should_use_cache_in_transaction
    ActiveRecord::Base.transaction do
      assert_equal false, IdentityCache.should_use_cache?
    end
  end
end

class IdentityCacheWithoutTransactionalFixturesTest < ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  if respond_to?(:use_transactional_tests)
    self.use_transactional_tests = false
  else
    self.use_transactional_fixtures = false
  end
  self.test_order = :random


  def test_should_use_cache_outside_transaction
    assert_equal true, IdentityCache.should_use_cache?
  end

  def test_should_use_cache_in_transaction
    ActiveRecord::Base.transaction do
      assert_equal false, IdentityCache.should_use_cache?
    end
  end
end
