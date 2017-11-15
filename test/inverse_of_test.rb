require "test_helper"

class InverseOfTest < IdentityCache::TestCase
  def setup
    super

    @item = Item.create!(:title => 'bob')

    AssociatedRecord.create!(:item => @item)
    AssociatedRecord.create!(:item => @item)
    AssociatedRecord.create!(:item => @item)
  end

  def test_fetch_should_setup_association_for_cache_belongs_to
    Item.cache_belongs_to :associated

    item = Item.find_by_id(@item.id)

    record = item.fetch_associated
    assert_equal item.object_id, record.item.object_id
  end

  def test_fetch_should_setup_association_for_cache_has_one
    Item.cache_has_one :associated

    item = Item.find_by_id(@item.id)

    record = item.fetch_associated
    assert_equal item.object_id, record.item.object_id
  end

  def test_fetch_should_setup_association_for_cache_has_many
    Item.cache_has_many :associated_records

    item = Item.find_by_id(@item.id)

    records = item.fetch_associated_records
    records.each do |r|
      assert_equal item.object_id, r.item.object_id
    end
  end

  def test_fetch_should_setup_association_for_cache_has_many_embedded
    Item.cache_has_many :associated_records, :embed => true

    item = Item.find_by_id(@item.id)

    records = item.fetch_associated_records
    records.each do |r|
      assert_equal item.object_id, r.item.object_id
    end
  end
end
