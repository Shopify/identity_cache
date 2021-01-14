# frozen_string_literal: true
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
        include(IdentityCache)
      end
    end
  end
end

class IdentityCacheWithTransactionalFixturesTest < ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  self.use_transactional_tests = true

  class ModelWithConnection < ActiveRecord::Base
    if ActiveRecord.gem_version < Gem::Version.new('6.1.0.alpha')
      establish_connection ActiveRecord::Base.connection_config
    else
      establish_connection ActiveRecord::Base.connection_db_config
    end
  end

  def test_should_use_cache_outside_transaction
    assert_equal(true, IdentityCache.should_use_cache?)
  end

  def test_should_use_cache_in_transaction
    ActiveRecord::Base.transaction do
      assert_equal(false, IdentityCache.should_use_cache?)
    end
  end

  def test_should_use_cache_in_transaction_on_specific_model
    ModelWithConnection.transaction do
      assert_equal(false, IdentityCache.should_use_cache?)
    end
  end
end

class IdentityCacheWithoutTransactionalFixturesTest < ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  self.use_transactional_tests = false

  class ModelWithConnection < ActiveRecord::Base
    if ActiveRecord.gem_version < Gem::Version.new('6.1.0.alpha')
      establish_connection ActiveRecord::Base.connection_config
    else
      establish_connection ActiveRecord::Base.connection_db_config
    end
  end

  def test_should_use_cache_outside_transaction
    assert_equal(true, IdentityCache.should_use_cache?)
  end

  def test_should_use_cache_in_transaction
    ActiveRecord::Base.transaction do
      assert_equal(false, IdentityCache.should_use_cache?)
    end
  end

  def test_should_use_cache_in_transaction_on_specific_model
    ModelWithConnection.transaction do
      assert_equal(false, IdentityCache.should_use_cache?)
    end
  end

  def test_should_use_inline_expirator_by_default
    assert_instance_of IdentityCache::InlineExpirator, IdentityCache.expirator
  end

  def test_should_be_able_to_set_expirator_to_worker
    with_expiration_strategy(:worker) do
      assert_instance_of IdentityCache::NoopExpirator, IdentityCache.expirator
    end
  end

  def test_should_raise_when_expiration_strategy_is_not_supported
    error = assert_raises(IdentityCache::ExpirationStrategyNotFound) do 
      with_expiration_strategy(:hope) do
        IdentityCache.expirator
      end
    end

    assert_equal "hope is not a valid expiration strategy", error.message
  end
end
