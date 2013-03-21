require "test_helper"

class SchemaChangeTest < IdentityCache::TestCase
  class AddCoulmnToChild < ActiveRecord::Migration
    def up
      add_column :associated_records, :shiny, :string
    end

    def down
      remove_column :associated_records, :shiny
    end
  end


  def setup
    super
    ActiveRecord::Migration.verbose = false
    Record.cache_has_one :associated
    Record.cache_index :title, :unique => true
    @record = Record.new(:title => 'foo')
    @record.associated = AssociatedRecord.new(:name => 'bar')
    @record.save

    @record.reload
  end

  def test_schema_changes_on_embedded_association_when_the_cached_object_is_already_loaded_in_memmory_should_not_use_the_embedded_cache
    Record.fetch(1)
    AddCoulmnToChild.new.up
    AssociatedRecord.reset_column_information

    assert_nothing_raised { Record.fetch(1).fetch_associated.shiny }
  end

  def teardown
    AddCoulmnToChild.new.down
    ActiveRecord::Migration.verbose = true
  end
end
