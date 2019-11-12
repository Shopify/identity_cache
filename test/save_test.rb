# frozen_string_literal: true
require "test_helper"

class SaveTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    Item.cache_index(:title, unique: true)
    Item.cache_index(:id, :title, unique: true)

    @record = Item.create(title: 'bob')
    @blob_key_prefix = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:"
    @blob_key = "#{@blob_key_prefix}1"
  end

  def test_create
    @record = Item.new
    @record.title = 'bob'

    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"2"/"bob"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"bob"')}")
    expect_cache_delete("#{@blob_key_prefix}2").once
    @record.save
  end

  def test_update
    # Regular flow, write index id, write index id/tile, delete data blob since Record has changed
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"1"/"fred"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"fred"')}")
    expect_cache_delete(@blob_key)

    # Delete index id, delete index id/title
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"1"/"bob"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"bob"')}")

    @record.title = 'fred'
    @record.save
  end

  def test_destroy
    # Regular flow: delete data blob, delete index id, delete index id/tile
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"1"/"bob"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"bob"')}")
    expect_cache_delete(@blob_key)

    @record.destroy
  end

  def test_destroy_with_changed_attributes
    # Make sure to delete the old cache index key, since the new title never ended up in an index
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"1"/"bob"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"bob"')}")
    expect_cache_delete(@blob_key)

    @record.title = 'fred'
    @record.destroy
  end

  def test_touch_will_expire_the_caches
    # Regular flow: delete data blob, delete index id, delete index id/tile
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"1"/"bob"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"bob"')}")
    expect_cache_delete(@blob_key)

    @record.touch
  end

  def test_expire_cache_works_in_a_transaction
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash('"1"/"bob"')}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"bob"')}")
    expect_cache_delete(@blob_key)

    ActiveRecord::Base.transaction do
      @record.expire_cache
    end
  end

  private

  def expect_cache_delete(key)
    @backend.expects(:write).with(key, IdentityCache::DELETED, anything)
  end
end
