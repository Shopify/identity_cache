# frozen_string_literal: true
require "test_helper"

class DeeplyNestedAssociatedRecordHasOneTest < IdentityCache::TestCase
  def test_deeply_nested_models_can_cache_has_one_associations
    assert_nothing_raised do
      PolymorphicRecord.include(IdentityCache::WithoutPrimaryIndex)
      Deeply::Nested::AssociatedRecord.has_one(:polymorphic_record, as: 'owner')
      Deeply::Nested::AssociatedRecord.cache_has_one(:polymorphic_record, inverse_name: :owner)
    end
  end

  def test_deeply_nested_models_can_cache_has_many_associations
    assert_nothing_raised do
      PolymorphicRecord.include(IdentityCache)
      Deeply::Nested::AssociatedRecord.has_many(:polymorphic_records, as: 'owner')
      Deeply::Nested::AssociatedRecord.cache_has_many(:polymorphic_records, inverse_name: :owner)
    end
  end
end
