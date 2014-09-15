require "test_helper"

class NormalizedHasOneTest < IdentityCache::TestCase
  def test_not_implemented_error
    assert_raises(NotImplementedError) do
      Item.cache_has_one :associated, :embed => false
    end
  end
end

class NormalizedHasOneSnappyPackTest < NormalizedHasOneTest
  def setup
    @snappy_pack = true
    super
  end
end

