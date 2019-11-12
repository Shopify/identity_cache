# frozen_string_literal: true
require "test_helper"

class FetchMultiByTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    @bob = Item.new
    @bob.id = 1
    @bob.title = 'bob'

    @bertha = Item.new
    @bertha.id = 2
    @bertha.title = 'bertha'
  end

  def test_fetch_multi_by_cache_key
    Item.cache_index(:title, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal([@bob], Item.fetch_by_title('bob'))

    assert_equal([@bob, @bertha], Item.fetch_multi_by_title(['bob', 'bertha']))
  end

  def test_fetch_multi_by_cache_key_with_unknown_key
    Item.cache_index(:title, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal([@bob], Item.fetch_multi_by_title(['bob', 'garbage_title']))
  end

  def test_fetch_multi_by_unique_cache_key
    Item.cache_index(:title, unique: true)

    @bob.save!
    @bertha.save!

    assert_equal(@bob, Item.fetch_by_title('bob'))

    assert_equal([@bob, @bertha], Item.fetch_multi_by_title(['bob', 'bertha']))
  end

  def test_fetch_multi_attribute_by_cache_key
    Item.cache_attribute(:title, by: :id, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal(['bob'], Item.fetch_title_by_id(1))

    assert_equal({ 1 => ['bob'], 2 => ['bertha'] }, Item.fetch_multi_title_by_id([1, 2]))
  end

  def test_fetch_multi_attribute_by_cache_key_with_unknown_key
    Item.cache_attribute(:title, by: :id, unique: false)

    @bob.save!
    @bertha.save!

    assert_equal({ 1 => ['bob'], 999 => [] }, Item.fetch_multi_title_by_id([1, 999]))
  end

  def test_fetch_multi_attribute_by_unique_cache_key
    Item.cache_attribute(:title, by: :id, unique: true)

    @bob.save!
    @bertha.save!

    assert_equal('bob', Item.fetch_title_by_id(1))

    assert_equal({ 1 => 'bob', 2 => 'bertha' }, Item.fetch_multi_title_by_id([1, 2]))
  end

  def test_fetch_multi_attribute_by_unique_cache_key_with_unknown_key
    Item.cache_attribute(:title, by: :id, unique: true)

    @bob.save!
    @bertha.save!

    assert_equal({ 1 => 'bob', 999 => nil }, Item.fetch_multi_title_by_id([1, 999]))
  end
end
