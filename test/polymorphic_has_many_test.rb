require 'test_helper'

class PolymorphicHasManyTest < IdentityCache::TestCase
  def setup
    super
    PolymorphicRecord.include(IdentityCache)

    Item.cache_has_many(:polymorphic_records, inverse_name: :owner)
    ItemTwo.cache_has_many(:polymorphic_records, inverse_name: :owner)
  end

  def test_polymorphic_has_many_filters_by_type
    item = Item.create(id: 1)
    item2 = ItemTwo.create(id: 1)

    poly1 = item.polymorphic_records.create
    poly2 = item.polymorphic_records.create
    poly3 = item2.polymorphic_records.create

    assert_equal([poly1, poly2], Item.fetch(1).fetch_polymorphic_records)
  end
end
