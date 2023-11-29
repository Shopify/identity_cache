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
  end

  def test_fetch_parent
    assert_nothing_raised do
      CustomParentRecord.fetch(@parent_record.parent_primary_key)
    end
  end
end
