require "test_helper"
require "irb"

class LazyHookTest < IdentityCache::TestCase
  def test_expires_unloaded_lazy_parent_models
    # Populate cache
    a = LazyLoad::A.create!(name: "Initial A")
    b = a.bs.create!(name: "Initial B")
    c = b.create_c!(name: "Initial C")

    ids = {
      a: a.id,
      b: b.id,
      c: c.id,
    }

    # Warm cache
    LazyLoad::A.fetch(ids[:a]).fetch_bs.first.fetch_c

    # Clear lazyloaded code to simulate code that isn't eager loaded
    reset_loaded_code
    LazyLoad::C.find(ids[:c]).update!(name: "Updated C")

    # Reload from IDC
    queries = count_queries do
      c = LazyLoad::A.fetch(ids[:a]).fetch_bs.first.fetch_c
      assert_equal("Updated C", c.name)
    end

    assert_equal(0, queries)
  end

  private

  def reset_loaded_code
    teardown_models
    setup_models
  end
end
