# frozen_string_literal: true

require "test_helper"

class SaveTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    Item.cache_index :title, :unique => true
    Item.cache_index :id, :title, :unique => true

    @record = Item.create(:title => 'bob')
    @blob_cache_hash = cache_hash(
      "created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime",
    )
  end

  def test_create
    @record = Item.new
    @record.title = 'bob'

    expect_cache_delete("blob:Item:#{@blob_cache_hash}:2")
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('2/bob')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}")
    @record.save
  end

  def test_create_with_alternate_key
    with_alternate_key do
      @record = Item.new
      @record.title = 'bob'

      expect_cache_delete("blob:Item:#{@blob_cache_hash}:2", alt: true).once
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('2/bob')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}", alt: true)
      @record.save
    end
  end

  def test_update
    # Regular flow, write index id, write index id/tile, delete data blob since Record has changed
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/fred')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('fred')}")
    expect_cache_delete("blob:Item:#{@blob_cache_hash}:1")

    # Delete index id, delete index id/title
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}")

    @record.title = 'fred'
    @record.save
  end

  def test_update_with_alternate_key
    with_alternate_key do
      # Regular flow, write index id, write index id/tile, delete data blob since Record has changed
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/fred')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('fred')}", alt: true)
      expect_cache_delete("blob:Item:#{@blob_cache_hash}:1", alt: true)

      # Delete index id, delete index id/title
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}", alt: true)

      @record.title = 'fred'
      @record.save
    end
  end

  def test_destroy
    # Regular flow: delete data blob, delete index id, delete index id/tile
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}")
    expect_cache_delete("blob:Item:#{@blob_cache_hash}:1")

    @record.destroy
  end

  def test_destroy_with_alternate_key
    with_alternate_key do
      # Regular flow: delete data blob, delete index id, delete index id/tile
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}", alt: true)
      expect_cache_delete("blob:Item:#{@blob_cache_hash}:1", alt: true)

      @record.destroy
    end
  end

  def test_destroy_with_changed_attributes
    # Make sure to delete the old cache index key, since the new title never ended up in an index
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}")
    expect_cache_delete("blob:Item:#{@blob_cache_hash}:1")

    @record.title = 'fred'
    @record.destroy
  end

  def test_destroy_with_changed_attributes_and_alternate_key
    with_alternate_key do
      # Make sure to delete the old cache index key, since the new title never ended up in an index
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}", alt: true)
      expect_cache_delete("blob:Item:#{@blob_cache_hash}:1", alt: true)

      @record.title = 'fred'
      @record.destroy
    end
  end

  def test_touch_will_expire_the_caches
    # Regular flow: delete data blob, delete index id, delete index id/tile
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}")
    expect_cache_delete("blob:Item:#{@blob_cache_hash}:1")

    @record.touch
  end

  def test_touch_will_expire_the_caches_with_alternate_key
    with_alternate_key do
      # Regular flow: delete data blob, delete index id, delete index id/tile
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}", alt: true)
      expect_cache_delete("blob:Item:#{@blob_cache_hash}:1", alt: true)

      @record.touch
    end
  end

  def test_expire_cache_works_in_a_transaction
    expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}")
    expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}")
    expect_cache_delete("blob:Item:#{@blob_cache_hash}:1")

    ActiveRecord::Base.transaction do
      @record.send(:expire_cache)
    end
  end

  def test_expire_cache_works_in_a_transaction_with_alternate_key
    with_alternate_key do
      expect_cache_delete("attr:Item:id:id/title:#{cache_hash('1/bob')}", alt: true)
      expect_cache_delete("attr:Item:id:title:#{cache_hash('bob')}", alt: true)
      expect_cache_delete("blob:Item:#{@blob_cache_hash}:1", alt: true)

      ActiveRecord::Base.transaction do
        @record.send(:expire_cache)
      end
    end
  end

  private

  def with_alternate_key
    IdentityCache.alternate_cache_namespace = "#{IdentityCache.cache_namespace}alt:"
    yield
  ensure
    IdentityCache.alternate_cache_namespace = nil
  end

  def expect_cache_delete(key, alt: false)
    @backend
      .expects(:write)
      .with("#{NAMESPACE}#{key}", IdentityCache::DELETED, anything)
      .once
    if alt
      @backend
        .expects(:write)
        .with("#{NAMESPACE}alt:#{key}", IdentityCache::DELETED, anything)
        .once
    end
  end
end
