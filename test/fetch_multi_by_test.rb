# frozen_string_literal: true

require "test_helper"

class FetchMultiByTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    @bob = Item.new
    @bob.id = 1
    @bob.item_id = 100
    @bob.title = "bob"

    @bertha = Item.new
    @bertha.id = 2
    @bertha.item_id = 100
    @bertha.title = "bertha"
  end

  def test_fetch_multi_by_cache_key
    Item.cache_index(:title, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal([@bob], Item.fetch_by_title("bob"))

    assert_equal([@bob, @bertha], Item.fetch_multi_by_title(["bob", "bertha"]))
  end

  def test_fetch_multi_by_cache_key_with_unknown_key
    Item.cache_index(:title, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal([@bob], Item.fetch_multi_by_title(["bob", "garbage_title"]))
  end

  def test_fetch_multi_by_unique_cache_key
    Item.cache_index(:title, unique: true)

    @bob.save!
    @bertha.save!

    assert_equal(@bob, Item.fetch_by_title("bob"))

    assert_equal([@bob, @bertha], Item.fetch_multi_by_title(["bob", "bertha"]))
  end

  def test_fetch_multi_attribute_by_cache_key
    Item.cache_attribute(:title, by: :id, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal(["bob"], Item.fetch_title_by_id(1))

    assert_equal({ 1 => ["bob"], 2 => ["bertha"] }, Item.fetch_multi_title_by_id([1, 2]))
  end

  def test_fetch_multi_attribute_by_cache_key_with_unknown_key
    Item.cache_attribute(:title, by: :id, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal({ 1 => ["bob"], 999 => [] }, Item.fetch_multi_title_by_id([1, 999]))
  end

  def test_fetch_multi_attribute_by_unique_cache_key
    Item.cache_attribute(:title, by: :id, unique: true)

    @bob.save!
    @bertha.save!

    assert_equal("bob", Item.fetch_title_by_id(1))

    assert_equal({ 1 => "bob", 2 => "bertha" }, Item.fetch_multi_title_by_id([1, 2]))
  end

  def test_fetch_multi_attribute_by_unique_cache_key_with_unknown_key
    Item.cache_attribute(:title, by: :id, unique: true)

    @bob.save!
    @bertha.save!

    assert_equal({ 1 => "bob", 999 => nil }, Item.fetch_multi_title_by_id([1, 999]))
  end

  def test_fetch_multi_attribute_by_with_empty_keys_without_using_cache
    Item.cache_index(:id, :title, unique: false)

    @bob.save!
    @bertha.save!

    records = Item.transaction { Item.fetch_multi_by_id_and_title([]) }
    assert_equal([], records)
  end

  def test_fetch_multi_attribute_by_with_composite_key
    Item.cache_index(:id, :title, unique: false)

    @bob.save!
    @bertha.save!

    assert_fetch_multi_with_composite_key(
      given: -> { Item.fetch_multi_by_id_and_title([[1, "bob"], [2, "bertha"]]) },
      expect_query: Item.select(:id, :title).where(id: 1, title: "bob").or(
        Item.select(:id, :title).where(id: 2, title: "bertha")
      ),
      returning: [@bob, @bertha]
    )
  end

  def test_fetch_multi_attribute_by_with_composite_key_and_unknown_keys
    Item.cache_index(:id, :title, unique: false)

    @bob.save!
    @bertha.save!

    assert_fetch_multi_with_composite_key(
      given: -> { Item.fetch_multi_by_id_and_title([[1, "bob"], [999, "bertha"]]) },
      expect_query: Item.select(:id, :title).where(id: 1, title: "bob").or(
        Item.select(:id, :title).where(id: 999, title: "bertha")
      ),
      returning: [@bob]
    )
  end

  def test_fetch_multi_attribute_by_with_composite_key_and_unique_cache_key
    Item.cache_index(:id, :title, unique: true)

    @bob.save!
    @bertha.save!

    assert_fetch_multi_with_composite_key(
      given: -> { Item.fetch_multi_by_id_and_title([[1, "bob"], [2, "bertha"]]) },
      expect_query: Item.select(:id, :title).where(id: 1, title: "bob").or(
        Item.select(:id, :title).where(id: 2, title: "bertha")
      ),
      returning: [@bob, @bertha]
    )
  end

  def test_fetch_multi_attribute_by_with_single_key
    Item.cache_index(:id, :title, unique: false)

    @bob.save!

    assert_fetch_multi_with_composite_key(
      given: -> { Item.fetch_multi_by_id_and_title([[1, "bob"]]) },
      expect_query: Item.select(:id, :title).where(id: 1, title: "bob"),
      returning: [@bob]
    )
  end

  def test_fetch_multi_attribute_by_with_implicit_in_query
    Item.cache_index(:item_id, :title, unique: true)

    @bob.save!
    @bertha.save!

    assert_fetch_multi_with_composite_key(
      given: -> { Item.fetch_multi_by_item_id_and_title([[100, "bob"], [100, "bertha"]]) },
      expect_query: Item.select(:id, :item_id, :title).where(item_id: 100, title: ["bob", "bertha"]),
      returning: [@bob, @bertha]
    )
  end

  def test_fetch_multi_attribute_by_with_mix_of_unique_and_common_attributes
    Item.cache_index(:id, :item_id, :title, unique: true)

    @bob.save!
    @bertha.save!

    assert_fetch_multi_with_composite_key(
      given: -> { Item.fetch_multi_by_id_and_item_id_and_title([[1, 100, "bob"], [2, 100, "bertha"]]) },
      expect_query: Item.select(:id, :item_id, :title).where(item_id: 100).merge(
        Item.select(:id, :item_id, :title).where(id: 1, title: "bob").or(
          Item.select(:id, :item_id, :title).where(id: 2, title: "bertha")
        )
      ),
      returning: [@bob, @bertha]
    )
  end

  private

  def assert_fetch_multi_with_composite_key(**options)
    given_query = options[:given]
    expected_query = options[:expect_query]
    expected_entities = options[:returning]
    result = assert_queries_sql(
      [expected_query.to_sql, Item.where(id: expected_entities.map(&:id)).to_sql],
      &given_query
    )
    assert_equal(expected_entities, result)
  end
end
