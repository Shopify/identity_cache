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
    Item.cache_has_one :associated, :embed => true
    AssociatedRecord.cache_has_many :deeply_associated_records, :embed => true

    @associated_record = AssociatedRecord.new(:name => 'bar')
    @deeply_associated_record = DeeplyAssociatedRecord.new(:name => "corge")
    @associated_record.deeply_associated_records << @deeply_associated_record
    @associated_record.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "qux")
    @record = Item.new(:title => 'foo')
    @record.associated = @associated_record

    @associated_record.save!
    @record.save!

    @record.reload
  end

  def teardown
    active_records = [AssociatedRecord, DeeplyAssociatedRecord]
    super
    active_records.each {|ar| ar.reset_column_information }
  end

  # This helper simulates the models being reloaded
  def read_new_schema
    AssociatedRecord.reset_column_information
    DeeplyAssociatedRecord.reset_column_information

    AssociatedRecord.send(:instance_variable_set, :@rails_cache_key_prefix, nil)
    Item.send(:instance_variable_set, :@rails_cache_key_prefix, nil)
  end

  def test_schema_changes_on_embedded_association_should_cause_cache_miss_for_old_cached_objects
    record = Item.fetch(@record.id)
    record.fetch_associated

    AddColumnToChild.new.up
    read_new_schema

    Item.expects(:resolve_cache_miss).returns(@record)
    record = Item.fetch(@record.id)
  end

  def test_schema_changes_on_deeply_embedded_association_should_cause_cache_miss_for_old_cached_objects
    record = Item.fetch(@record.id)
    associated_record_from_cache = record.fetch_associated
    associated_record_from_cache.fetch_deeply_associated_records

    AddColumnToDeepChild.new.up
    read_new_schema

    Item.expects(:resolve_cache_miss).returns(@record)
    record = Item.fetch(@record.id)
  end

  def test_schema_changes_on_new_cached_child_association
    record = Item.fetch(@record.id)

    Item.cache_has_many :polymorphic_records, :inverse_name => :owner, :embed => true
    read_new_schema

    Item.expects(:resolve_cache_miss).returns(@record)
    record = Item.fetch(@record.id)
  end

  def test_embed_existing_cache_has_many
    Item.cache_has_many :polymorphic_records, :inverse_name => :owner, :embed => false
    read_new_schema

    record = Item.fetch(@record.id)

    Item.cache_has_many :polymorphic_records, :inverse_name => :owner, :embed => true
    read_new_schema

    Item.expects(:resolve_cache_miss).returns(@record)
    record = Item.fetch(@record.id)
  end
end
