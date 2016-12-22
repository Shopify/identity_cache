require "test_helper"

class DeeplyNestedAssociatedRecordHasOneTest < IdentityCache::TestCase
  def test_deeply_nested_models_can_cache_has_one_associations
    assert_nothing_raised do
      Deeply::Nested::AssociatedRecord.has_one :polymorphic_record, as: 'owner', inverse_of: :owner
      Deeply::Nested::AssociatedRecord.cache_has_one :polymorphic_record
    end
  end

  def test_deeply_nested_models_can_cache_has_many_associations
    assert_nothing_raised do
      PolymorphicRecord.include(IdentityCache)
      Deeply::Nested::AssociatedRecord.has_many :polymorphic_records, as: 'owner', inverse_of: :owner
      Deeply::Nested::AssociatedRecord.cache_has_many :polymorphic_records
    end
  end
end
