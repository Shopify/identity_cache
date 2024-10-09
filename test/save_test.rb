# frozen_string_literal: true

require "test_helper"

class SaveTest < IdentityCache::TestCase
  NAMESPACE   = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE
  ATTR_STRING = "created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime"

  def setup
    super
    Item.cache_index(:title, unique: true)
    Item.cache_index(:id, :title, unique: true)

    @record = Item.create(title: "bob", created_at: 1.second.ago, updated_at: 1.second.ago)
    @blob_key_prefix = [
      NAMESPACE, "blob:", "Item:", "#{cache_hash(ATTR_STRING)}:",
    ].join
    @blob_key = "#{@blob_key_prefix}1"
  end

  def test_create
    @record = Item.new
    @record.title = "bob"

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

    @record.title = "fred"
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

    @record.title = "fred"
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

  def test_touch_with_separate_calls
    @record1 = Item.create(title: "fooz", created_at: 1.second.ago, updated_at: 1.second.ago)
    @record2 = Item.create(title: "barz", created_at: 1.second.ago, updated_at: 1.second.ago)
    id_and_title_key1 = "\"#{@record1.id}\"/\"fooz\""
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash(id_and_title_key1)}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"fooz"')}")
    id_and_title_key2 = "\"#{@record2.id}\"/\"barz\""
    expect_cache_delete("#{NAMESPACE}attr:Item:id:id/title:#{cache_hash(id_and_title_key2)}")
    expect_cache_delete("#{NAMESPACE}attr:Item:id:title:#{cache_hash('"barz"')}")
    expect_cache_delete(@record1.primary_cache_index_key)
    expect_cache_delete(@record2.primary_cache_index_key)

    ActiveRecord::Base.transaction do
      @record1.touch
      @record2.touch
    end
  end

  def test_touch_with_batched_calls
    @record1 = Item.create(title: "fooz", created_at: 1.second.ago, updated_at: 1.second.ago)
    @record2 = Item.create(title: "barz", created_at: 1.second.ago, updated_at: 1.second.ago)
    id_and_title_key1 = "\"#{@record1.id}\"/\"fooz\""
    id_and_title_key2 = "\"#{@record2.id}\"/\"barz\""
    expect_cache_deletes([
      "#{NAMESPACE}attr:Item:id:title:#{cache_hash('"fooz"')}",
      "#{NAMESPACE}attr:Item:id:id/title:#{cache_hash(id_and_title_key1)}",
      "#{NAMESPACE}attr:Item:id:title:#{cache_hash('"barz"')}",
      "#{NAMESPACE}attr:Item:id:id/title:#{cache_hash(id_and_title_key2)}",
    ])
    expect_cache_deletes([@record1.primary_cache_index_key, @record2.primary_cache_index_key])

    IdentityCache.with_deferred_attribute_expiration do
      ActiveRecord::Base.transaction do
        @record1.touch
        @record2.touch
      end
    end
  end

  private

  def expect_cache_delete(key)
    @backend.expects(:write).with(key, IdentityCache::DELETED, anything)
  end

  def expect_cache_deletes(keys)
    key_values = keys.map { |key| [key, IdentityCache::DELETED] }
    @backend.expects(:write_multi).with(key_values, anything)
  end
end
