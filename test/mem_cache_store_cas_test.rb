require "test_helper"

class MemCacheStoreCasTest < IdentityCache::TestCase
  def setup
    super
    @cache = backend
  end

  def test_cas_with_cache_miss
    refute(
      @cache.cas("not_exist") do |_value|
        flunk
      end,
    )
  end

  def test_cas_with_conflict
    @cache.write("foo", "bar")
    refute(
      @cache.cas("foo") do |_value|
        @cache.write("foo", "baz")
        "biz"
      end,
    )
    assert_equal "baz", @cache.read("foo")
  end

  def test_cas_multi_with_empty_set
    refute(
      @cache.cas_multi do |_values|
        flunk
      end,
    )
  end

  def test_cas_multi
    @cache.write("foo", "bar")
    @cache.write("fud", "biz")
    assert(
      @cache.cas_multi("foo", "fud") do |values|
        assert_equal({ "foo" => "bar", "fud" => "biz" }, values)
        { "foo" => "baz", "fud" => "buz" }
      end,
    )
    assert_equal({ "foo" => "baz", "fud" => "buz" }, @cache.read_multi("foo", "fud"))
  end

  def test_cas_multi_with_altered_key
    @cache.write("foo", "baz")
    assert(
      @cache.cas_multi("foo") do |_values|
        { "fu" => "baz" }
      end,
    )
    assert_nil @cache.read("fu")
    assert_equal "baz", @cache.read("foo")
  end

  def test_cas_multi_with_cache_miss
    assert(
      @cache.cas_multi("not_exist") do |values|
        assert values.empty?
        {}
      end,
    )
  end

  def test_cas_multi_with_partial_miss
    @cache.write("foo", "baz")
    assert(
      @cache.cas_multi("foo", "bar") do |values|
        assert_equal({ "foo" => "baz" }, values)
        {}
      end,
    )
    assert_equal "baz", @cache.read("foo")
  end

  def test_cas_multi_with_partial_update
    @cache.write("foo", "bar")
    @cache.write("fud", "biz")
    assert(
      @cache.cas_multi("foo", "fud") do |values|
        assert_equal({ "foo" => "bar", "fud" => "biz" }, values)
        { "foo" => "baz" }
      end,
    )
    assert_equal({ "foo" => "baz", "fud" => "biz" }, @cache.read_multi("foo", "fud"))
  end

  def test_cas_multi_with_partial_conflict
    @cache.write("foo", "bar")
    @cache.write("fud", "biz")
    assert(
      @cache.cas_multi("foo", "fud") do |values|
        assert_equal({ "foo" => "bar", "fud" => "biz" }, values)
        @cache.write("foo", "bad")
        { "foo" => "baz", "fud" => "buz" }
      end,
    )
    assert_equal({ "foo" => "bad", "fud" => "buz" }, @cache.read_multi("foo", "fud"))
  end

  def test_cas_with_read_only_memcached_store_should_not_s
    called_block = false
    @cache.write("walrus", "slimy")

    with_read_only(@cache) do
      assert(
        @cache.cas("walrus") do |value|
          assert_equal "slimy", value
          called_block = true
          "full"
        end,
      )
    end

    assert_equal "slimy", @cache.read("walrus")
    assert called_block, "CAS with read only should have called the inner block with an assertion"
  end

  def test_cas_multi_with_read_only_memcached_store_should_not_s
    called_block = false

    @cache.write("walrus", "cool")
    @cache.write("narwhal", "horn")

    with_read_only(@cache) do
      assert(
        @cache.cas_multi("walrus", "narwhal") do
          called_block = true
          { "walrus" => "not cool", "narwhal" => "not with horns" }
        end,
      )
    end

    assert_equal "cool", @cache.read("walrus")
    assert_equal "horn", @cache.read("narwhal")
    assert called_block, "CAS with read only should have called the inner block with an assertion"
  end

  def test_cas_with_read_only_should_send_activesupport_notification
    @cache.write("walrus", "yes")

    with_read_only(@cache) do
      assert_notifications(/cache_cas/, 1) do
        assert(
          @cache.cas("walrus") do |_value|
            "no"
          end,
        )
      end
    end

    assert_equal "yes", @cache.fetch("walrus")
  end

  def test_cas_multi_with_read_only_should_send_activesupport_notification
    @cache.write("walrus", "yes")
    @cache.write("narwhal", "yes")

    with_read_only(@cache) do
      assert_notifications(/cache_cas/, 1) do
        assert(
          @cache.cas_multi("walrus", "narwhal") do |*_values|
            { "walrus" => "no", "narwhal" => "no" }
          end,
        )
      end
    end

    assert_equal "yes", @cache.fetch("walrus")
    assert_equal "yes", @cache.fetch("narwhal")
  end

  def test_cas_returns_false_on_error
    @cache.instance_variable_get(:@data).expects(:cas).raises(Dalli::DalliError)
    refute(
      @cache.cas("foo") do |_value|
        flunk
      end,
    )
  end

  def test_cas_multi_returns_false_on_error
    @cache.instance_variable_get(:@data).expects(:get_multi_cas).raises(Dalli::DalliError)
    refute(
      @cache.cas_multi("foo", "bar") do |_value|
        flunk
      end,
    )
  end

  private

  def assert_notifications(pattern, num)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe(pattern) do |_name, _start, _finish, _id, _payload|
      count += 1
    end

    yield

    assert_equal num, count, "Expected #{num} notifications for #{pattern}, but got #{count}"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def with_read_only(*)
    yield
  end
end
