# frozen_string_literal: true
require "test_helper"

class SchemaChangeTest < IdentityCache::TestCase
  Migration = ActiveRecord::Migration[5.2]

  class AddColumnToChild < Migration
    def up
      add_column(:associated_records, :shiny, :string)
    end
  end

  class AddColumnToDeepChild < Migration
    def up
      add_column(:deeply_associated_records, :new_column, :string)
    end
  end

  def setup
    super
    ActiveRecord::Migration.verbose = false

    read_new_schema
    Item.cache_has_one(:associated, embed: true)
    AssociatedRecord.cache_has_many(:deeply_associated_records, embed: true)

    @associated_record = AssociatedRecord.new(name: "bar")
    @deeply_associated_record = DeeplyAssociatedRecord.new(name: "corge")
    @associated_record.deeply_associated_records << @deeply_associated_record
    @associated_record.deeply_associated_records << DeeplyAssociatedRecord.new(name: "qux")
    @record = Item.new(title: "foo")
    @record.associated = @associated_record

    @associated_record.save!
    @record.save!

    @record.reload
  end

  def teardown
    active_records = [AssociatedRecord, DeeplyAssociatedRecord]
    super
    active_records.each(&:reset_column_information)
  end

  # This helper simulates the models being reloaded
  def read_new_schema
    AssociatedRecord.reset_column_information
    DeeplyAssociatedRecord.reset_column_information

    AssociatedRecord.cached_primary_index.send(:instance_variable_set, :@cache_key_prefix, nil)
    Item.cached_primary_index.send(:instance_variable_set, :@cache_key_prefix, nil)
  end

  def test_schema_changes_on_embedded_association_should_cause_cache_miss_for_old_cached_objects
    record = Item.fetch(@record.id)
    record.fetch_associated

    AddColumnToChild.new.up
    read_new_schema

    Item.cached_primary_index.expects(:load_one_from_db).returns(@record)
    Item.fetch(@record.id)
  end

  def test_schema_changes_on_deeply_embedded_association_should_cause_cache_miss_for_old_cached_objects
    record = Item.fetch(@record.id)
    associated_record_from_cache = record.fetch_associated
    associated_record_from_cache.fetch_deeply_associated_records

    AddColumnToDeepChild.new.up
    read_new_schema

    Item.cached_primary_index.expects(:load_one_from_db).returns(@record)
    Item.fetch(@record.id)
  end

  def test_schema_changes_on_new_cached_child_association
    Item.fetch(@record.id)

    PolymorphicRecord.include(IdentityCache::WithoutPrimaryIndex)
    Item.cache_has_many(:polymorphic_records, embed: true)
    read_new_schema

    Item.cached_primary_index.expects(:load_one_from_db).returns(@record)
    Item.fetch(@record.id)
  end

  def test_embed_existing_cache_has_many
    PolymorphicRecord.include(IdentityCache)
    Item.cache_has_many(:polymorphic_records, embed: :ids)
    read_new_schema

    Item.fetch(@record.id)

    teardown_models
    setup_models

    PolymorphicRecord.include(IdentityCache::WithoutPrimaryIndex)
    Item.cache_has_many(:polymorphic_records, embed: true)
    read_new_schema

    Item.fetch(@record.id)
  end

  def test_cache_reusable_after_associated_class_name_changes
    define_models = lambda do |associated_class_name|
      self.class.class_exec do
        associated_class = const_set(associated_class_name, Class.new(ActiveRecord::Base))
        item_class = const_set(:Item, Class.new(ActiveRecord::Base))

        associated_class.class_eval do
          self.table_name = "associated_records"
          include(IdentityCache::WithoutPrimaryIndex)
          belongs_to(:item, class_name: item_class.name)
        end

        item_class.class_eval do
          self.table_name = "items"
          include(IdentityCache)
          has_many(:associated_records, class_name: associated_class_name)
          cache_has_many(:associated_records, embed: true)
        end
      end
    end

    define_models.call(:AssociatedRecord)

    record = self.class::Item.fetch(@record.id) # warm cache
    assert_equal(["bar"], record.fetch_associated_records.map(&:name))

    self.class.send(:remove_const, :Item)
    self.class.send(:remove_const, :AssociatedRecord)
    define_models.call(:AssociatedRecordRenamed)

    assert_no_queries do
      record = self.class::Item.fetch(@record.id)
      assert_equal(["bar"], record.fetch_associated_records.map(&:name))
    end
  ensure
    self.class.send(:remove_const, :Item) if self.class.const_defined?(:Item, false)
    if self.class.const_defined?(:AssociatedRecordRenamed, false)
      self.class.send(:remove_const, :AssociatedRecordRenamed)
    end
  end

  def test_add_non_embedded_cache_has_many
    PolymorphicRecord.include(IdentityCache)
    Item.fetch(@record.id)

    Item.cache_has_many(:polymorphic_records, embed: :ids)
    read_new_schema

    Item.fetch(@record.id)
  end
end
