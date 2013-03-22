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

    AssociatedRecord.reset_column_information
    DeeplyAssociatedRecord.reset_column_information

    ActiveRecord::Migration.verbose = false
    Record.cache_has_one :associated
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

  def test_schema_changes_on_embedded_association_when_the_cached_object_is_already_in_the_cache_should_request_from_the_db
    record = Record.fetch(@record.id)
    AddColumnToChild.new.up
    AssociatedRecord.reset_column_information

    assert_nothing_raised { record.fetch_associated.shiny }

    assert_no_queries { record.fetch_associated.shiny }
    AddColumnToChild.new.down
  end

  def test_schema_changes_on_deeply_embedded_association_when_the_cached_object_is_already_in_the_cache_should_request_from_the_db
    record_from_cache = Record.fetch(@record.id)
    associated_record_from_cache = record_from_cache.fetch_associated

    AddColumnToDeepChild.new.up
    DeeplyAssociatedRecord.reset_column_information

    assert_nothing_raised do
      associated_record_from_cache.fetch_deeply_associated_records.map(&:new_column)
    end

    assert_no_queries do
      associated_record_from_cache.fetch_deeply_associated_records.each{ |obj| assert_nil obj.new_column }
      record_from_cache.fetch_associated.fetch_deeply_associated_records.each{ |obj| assert_nil obj.new_column }
    end

    AddColumnToDeepChild.new.down
  end
end
