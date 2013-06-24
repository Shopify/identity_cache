require "test_helper"

class TransactionDeleteBatchingTest < IdentityCache::TestCase
  def setup
    super
    IdentityCache.cache_backend = Rails.cache
  end

  def self.transaction(*)
    yield
  end
  include IdentityCache::TransactionDeleteBatching

  def test_batching_handles_exceptions
    c = IdentityCache.cache
    c.cache_backend.expects('delete').with('foo').once
    ex = Class.new(StandardError)

    assert_raises(ex) do
      self.class.transaction do
        c.delete('foo')
        raise ex
      end
    end
  end

end
