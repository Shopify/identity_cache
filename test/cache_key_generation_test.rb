# frozen_string_literal: true

require "test_helper"

module IdentityCache
  class CacheKeyGenerationTest < IdentityCache::TestCase
    NORMALIZED_SCHEMA_STRING = "created_at:datetime,id:integer,item_id:integer,item_two_id:integer," \
      "name:string,updated_at:datetime"

    def test_schema_string
      assert_equal(
        NORMALIZED_SCHEMA_STRING,
        CacheKeyGeneration.denormalized_schema_string(AssociatedRecord),
      )
    end

    def test_schema_string_with_recursive_has_many
      AssociatedRecord.cache_has_many(:deeply_associated_records, embed: true)

      assert_equal(
        "#{NORMALIZED_SCHEMA_STRING},deeply_associated_records:(319486821334646525)",
        CacheKeyGeneration.denormalized_schema_string(AssociatedRecord),
      )
    end

    def test_schema_string_with_referential_has_many
      AssociatedRecord.cache_has_many(:deeply_associated_records, embed: :ids)

      assert_equal(
        "#{NORMALIZED_SCHEMA_STRING},deeply_associated_records:ids",
        CacheKeyGeneration.denormalized_schema_string(AssociatedRecord),
      )
    end

    def test_schema_string_with_recursive_has_one
      AssociatedRecord.cache_has_one(:deeply_associated, embed: true)

      assert_equal(
        "#{NORMALIZED_SCHEMA_STRING},deeply_associated:(319486821334646525)",
        CacheKeyGeneration.denormalized_schema_string(AssociatedRecord),
      )
    end

    def test_schema_string_with_referential_has_one
      AssociatedRecord.cache_has_one(:deeply_associated, embed: :id)

      assert_equal(
        "#{NORMALIZED_SCHEMA_STRING},deeply_associated:id",
        CacheKeyGeneration.denormalized_schema_string(AssociatedRecord),
      )
    end

    def test_schema_string_with_belongs_to
      AssociatedRecord.cache_belongs_to(:item)

      # NOTE: Should be the same as a schema without cached assocaitions
      assert_equal(
        NORMALIZED_SCHEMA_STRING,
        CacheKeyGeneration.denormalized_schema_string(AssociatedRecord),
      )
    end
  end
end
