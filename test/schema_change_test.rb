require "test_helper"

class SchemaChangeTest < IdentityCache::TestCase
  class AddColumnToChild < ActiveRecord::Migration
    def up
      add_column :associated_records, :shiny, :string
    end

    def down
      remove_column :associated_records, :shiny
    end
  end

  class AddColumnToDeepChild < ActiveRecord::Migration
    def up
      add_column :deeply_associated_records, :new_column, :string
    end

    def down
      remove_column :deeply_associated_records, :new_column
    end
  end

  def setup
    super
    ActiveRecord::Migration.verbose = false

    read_new_schema
    Record.cache_has_one :associated, :embed => true
    Record.cache_index :title, :unique => true
    AssociatedRecord.cache_has_many :deeply_associated_records, :embed => true

    @associated_record = AssociatedRecord.new(:name => 'bar')
    @deeply_associated_record = DeeplyAssociatedRecord.new(:name => "corge")
    @associated_record.deeply_associated_records << @deeply_associated_record
    @associated_record.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "qux")
    @record = Record.new(:title => 'foo')
    @record.associated = @associated_record

    @associated_record.save!
    @record.save!

    @record.reload
  end

  # This helper simulates the models being reloaded
  def read_new_schema
    AssociatedRecord.reset_column_information
    DeeplyAssociatedRecord.reset_column_information

    AssociatedRecord.embedded_schema_hashes = {}
    Record.embedded_schema_hashes = {}
  end

  def test_schema_changes_on_embedded_association_when_the_cached_object_is_already_in_the_cache_should_request_from_the_db
    record = Record.fetch(@record.id)
    record.fetch_associated

    AddColumnToChild.new.up
    read_new_schema

    # Reloading the association queries
    # SHOW FULL FIELDS FROM `associated_records`
    # SHOW TABLES LIKE 'associated_records'
    # SELECT  `associated_records`.* FROM `associated_records`  WHERE `associated_records`.`record_id` = 1 ORDER BY id ASC LIMIT 1.
    assert_queries(3) do
      assert_nothing_raised { record.fetch_associated.shiny }
    end

    assert_no_queries { record.fetch_associated.shiny }
  end

  def test_schema_changes_on_deeply_embedded_association_when_the_cached_object_is_already_in_the_cache_should_request_from_the_db
    record = Record.fetch(@record.id)
    associated_record_from_cache = record.fetch_associated
    associated_record_from_cache.fetch_deeply_associated_records

    AddColumnToDeepChild.new.up
    read_new_schema

    # Loading association queries
    # SHOW FULL FIELDS FROM `deeply_associated_records`
    # SHOW FULL FIELDS FROM `associated_records`
    # SHOW TABLES LIKE 'deeply_associated_records'
    # SELECT `deeply_associated_records`.* FROM `deeply_associated_records` WHERE `deeply_associated_records`.`associated_record_id` = 1 ORDER BY name DESC.
    assert_queries(4) do
      assert_nothing_raised do
        associated_record_from_cache.fetch_deeply_associated_records.map(&:new_column)
      end
    end

    assert_no_queries do
      associated_record_from_cache.fetch_deeply_associated_records.each{ |obj| assert_nil obj.new_column }
      record.fetch_associated.fetch_deeply_associated_records.each{ |obj| assert_nil obj.new_column }
    end
  end
end
