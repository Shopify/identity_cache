require "test_helper"

class ExpireTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    Item.cache_index :title, :unique => true
    Item.cache_index :id, :title, :unique => true

    @record = Item.create(:title => 'bob')
    Item.fetch_by_id(@record.id)
    @blob_key = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:1"
  end

  def test_instance_force_expiration_will_expire_caches
    # Regular flow: delete data blob, delete index id, delete index id/tile
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Item:id/title:#{cache_hash('1/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Item:title:#{cache_hash('bob')}")
    IdentityCache.cache.expects(:delete).with(@blob_key)

    @record.force_expiration
  end

  def test_class_force_expiration_will_expire_caches
    # Regular flow: delete data blob, delete index id, delete index id/tile
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Item:id/title:#{cache_hash('1/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Item:title:#{cache_hash('bob')}")
    IdentityCache.cache.expects(:delete).with(@blob_key)

    Item.force_expiration(@record.id)
  end

  def test_class_force_expiration_without_cached_id_will_do_nothing
    IdentityCache.cache.expects(:delete).never
    Item.force_expiration(123)
  end
end
