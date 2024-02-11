# frozen_string_literal: true

require "test_helper"

class AssociationErrorTest < IdentityCache::TestCase
  def test_cache_belongs_to
    error = assert_raises(IdentityCache::AssociationError) do
      Item.send(:cache_belongs_to, :foo)
    end
    assert_equal("Association named 'foo' was not found on Item", error.message)
  end

  def test_cache_has_one
    error = assert_raises(IdentityCache::AssociationError) do
      Item.send(:cache_has_one, :foo, embed: true)
    end
    assert_equal("Association named 'foo' was not found on Item", error.message)
  end

  def test_cache_has_many
    error = assert_raises(IdentityCache::AssociationError) do
      Item.send(:cache_has_many, :foo)
    end
    assert_equal("Association named 'foo' was not found on Item", error.message)
  end
end
