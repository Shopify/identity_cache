require 'test_helper'

class SelfAssociationTest < IdentityCache::TestCase
  def setup
    super
    SelfItem.cache_has_many :associated_items, embed: true, inverse_name: :parent_item
    SelfItem.cache_belongs_to :parent_item
    @item = SelfItem.new(title: 'foo')
    @item.save

    @associated_item = SelfItem.new(title: 'bar')
    @associated_item.save

    @deeply_associated_item = SelfItem.new(title: 'baz')
    @deeply_associated_item.save

    SelfItemTwo.cache_has_many :self_items, embed: true
    SelfItemTwo.cache_belongs_to :self_item
    @other_item = SelfItemTwo.new(title: 'qux')
    @other_item.save
    @other_item_two = SelfItemTwo.new(title: 'quux')
    @other_item_two.save
  end

  def test_associating_record_with_itself_should_not_raise_exceptions
    assert_nothing_raised do
      @item.associated_items << SelfItem.new(title: 'bar')
      @item.save
    end
  end

  def test_self_associated_record_should_be_returned_on_cache_hit
    @item.associated_items << @associated_item
    @item.save

    SelfItem.fetch(@item.id)

    cached_item = SelfItem.fetch(@item.id)
    assert_equal @item, cached_item
    assert_equal [@associated_item], cached_item.associated_items
  end

  def test_multiple_self_assoc_levels_should_be_returned
    @associated_item.associated_items << @deeply_associated_item
    @item.associated_items << @associated_item

    @item.save
    @associated_item.save

    SelfItem.fetch(@item.id)

    cached_item = SelfItem.fetch(@item.id)
    assert_equal [@associated_item], cached_item.associated_items
    cached_assoc_item = cached_item.associated_items.first
    assert_equal [@deeply_associated_item], cached_assoc_item.associated_items
  end

  def test_self_assoc_should_include_other_associations
    @item.associated_items << @associated_item

    @item.self_item_twos << @other_item
    @associated_item.self_item_twos << @other_item_two

    @item.save
    @associated_item.save

    SelfItem.fetch(@item.id)

    cached_item = SelfItem.fetch(@item.id)
    assert_equal [@other_item], cached_item.self_item_twos
    assert_equal [@other_item_two], cached_item.associated_items.first.self_item_twos
  end

  def test_should_detect_cyclical_associations
    @item.self_item_twos << @other_item
    @other_item.self_items << @associated_item

    @item.save
    @other_item.save

    SelfItem.fetch(@item.id)

    cached_item = SelfItem.fetch(@item.id)
    assert_equal [@other_item], cached_item.self_item_twos
    assert_equal [@associated_item], cached_item.self_item_twos.first.self_items
  end
end
