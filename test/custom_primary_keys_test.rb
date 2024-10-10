# frozen_string_literal: true

require "test_helper"

class CustomPrimaryKeysTest < IdentityCache::TestCase
  def setup
    super
    CustomParentRecord.cache_has_many(:custom_child_records)
    CustomChildRecord.cache_belongs_to(:custom_parent_record)
    @parent_record = CustomParentRecord.create!(parent_primary_key: 1)
    @child_record_1 = CustomChildRecord.create!(custom_parent_record: @parent_record, child_primary_key: 1)
    @child_record_2 = CustomChildRecord.create!(custom_parent_record: @parent_record, child_primary_key: 2)

    CompositePrimaryKeyRecord.cache_has_many(:cpk_references)
    CPKReference.cache_belongs_to(:composite_primary_key_record)
    @composite_record = CompositePrimaryKeyRecord.create!(key_part_one: 1, key_part_two: 2)
    @cpk_reference = CPKReference.create!(composite_primary_key_record: @composite_record)
  end

  def test_fetch_parent
    assert_nothing_raised do
      CustomParentRecord.fetch(@parent_record.parent_primary_key)
    end
  end

  def test_fetch_composite_primary_key_record
    assert_nothing_raised do
      cpk_record = CompositePrimaryKeyRecord.fetch([@composite_record.key_part_one, @composite_record.key_part_two])
      refute_nil cpk_record
    end
  end
end
