require "test_helper"

class LazyHookTest < IdentityCache::TestCase
  def test_expires_unloaded_lazy_parent_models
    # Populate cache
    a = LazyModel::A.create!(name: "Initial A")
    b = a.bs.create!(name: "Initial B")
    c = b.create_c!(name: "Initial C")

    ids = {
      a: a.id,
      b: b.id,
      c: c.id,
    }

    # Warm cache
    LazyModel::A.fetch(ids[:a]).fetch_bs.first.fetch_c

    # Clear lazyloaded code to simulate code that isn't eager loaded
    reset_loaded_code
    LazyModel::C.find(ids[:c]).update!(name: "Updated C")

    refute(lazy_model_loaded?(:A))
    refute(lazy_model_loaded?(:B))

    queries = count_queries do
      c = LazyModel::A.fetch(ids[:a]).fetch_bs.first.fetch_c
      assert_equal("Updated C", c.name)
    end

    assert_equal(0, queries)
  end

  private

  def reset_loaded_code
    teardown_models
    setup_models
  end

  def lazy_model_loaded?(name)
    !LazyModel.autoload?(name)
  end
end
