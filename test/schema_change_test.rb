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
    Record.cache_has_one :associated
    Record.cache_index :title, :unique => true
    @record = Record.new(:title => 'foo')
    @record.associated = AssociatedRecord.new(:name => 'bar')
    @record.save

    @record.reload
  end

  def test_foo
    Record.fetch(1)
    AddCoulmnToChild.new.up
    AssociatedRecord.reset_column_information
    Record.fetch(1).fetch_associated.shiny
  end

  def teardown
    AddCoulmnToChild.new.down
  end
end
