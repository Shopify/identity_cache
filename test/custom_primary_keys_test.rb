# frozen_string_literal: true
require "test_helper"

class CustomPrimaryKeysTest < IdentityCache::TestCase
  def setup
    super
    CustomMasterRecord.cache_has_many(:custom_child_record)
    CustomChildRecord.cache_belongs_to(:custom_master_record)
    @master_record = CustomMasterRecord.create!(master_primary_key: 1)
    @child_record_1 = CustomChildRecord.create!(custom_master_record: @master_record, child_primary_key: 1)
    @child_record_2 = CustomChildRecord.create!(custom_master_record: @master_record, child_primary_key: 2)
  end

  def test_fetch_master
    assert_nothing_raised do
      CustomMasterRecord.fetch(@master_record.master_primary_key)
    end
  end
end
