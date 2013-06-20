require "test_helper"

class SchemaChangeTest < IdentityCache::TestCase
  class AddColumnToChild < ActiveRecord::Migration
    def up
      add_column :associated_records, :shiny, :string
    end
  end

  class AddColumnToDeepChild < ActiveRecord::Migration
    def up
      add_column :deeply_associated_records, :new_column, :string
    end
  end

  def setup
    super
    ActiveRecord::Migration.verbose = false

    read_new_schema
    Record.cache_has_one :associated, :embed => true
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

    AssociatedRecord.send(:instance_variable_set, :@rails_cache_key_prefix, nil)
    Record.send(:instance_variable_set, :@rails_cache_key_prefix, nil)
  end

  def test_schema_changes_on_embedded_association_should_cause_cache_miss_for_old_cached_objects
    record = Record.fetch(@record.id)
    record.fetch_associated

    AddColumnToChild.new.up
    read_new_schema

    Record.expects(:resolve_cache_miss).returns(@record)
    record = Record.fetch(@record.id)
  end

  def test_schema_changes_on_deeply_embedded_association_should_cause_cache_miss_for_old_cached_objects
    record = Record.fetch(@record.id)
    associated_record_from_cache = record.fetch_associated
    associated_record_from_cache.fetch_deeply_associated_records

    AddColumnToDeepChild.new.up
    read_new_schema

    Record.expects(:resolve_cache_miss).returns(@record)
    record = Record.fetch(@record.id)
  end

  def test_schema_changes_on_new_cached_child_association
    record = Record.fetch(@record.id)

    Record.cache_has_many :polymorphic_records, :inverse_name => :owner, :embed => true
    read_new_schema

    Record.expects(:resolve_cache_miss).returns(@record)
    record = Record.fetch(@record.id)
  end
end
