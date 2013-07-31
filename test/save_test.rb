require "test_helper"

class SaveTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super
    Record.cache_index :title, :unique => true
    Record.cache_index :id, :title, :unique => true

    @record = Record.create(:title => 'bob')
    @blob_key = "#{NAMESPACE}blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:1"
  end

  def test_create
    @record = Record.new
    @record.title = 'bob'

    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:id/title:#{cache_hash('2/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:title:#{cache_hash('bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:2").once
    @record.save
  end

  def test_update
    # Regular flow, write index id, write index id/tile, delete data blob since Record has changed
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:id/title:#{cache_hash('1/fred')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:title:#{cache_hash('fred')}")
    IdentityCache.cache.expects(:delete).with(@blob_key)

    # Delete index id, delete index id/title
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:id/title:#{cache_hash('1/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:title:#{cache_hash('bob')}")

    @record.title = 'fred'
    @record.save
  end

  def test_destroy
    # Regular flow: delete data blob, delete index id, delete index id/tile
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:id/title:#{cache_hash('1/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:title:#{cache_hash('bob')}")
    IdentityCache.cache.expects(:delete).with(@blob_key)

    @record.destroy
  end

  def test_destroy_with_changed_attributes
    # Make sure to delete the old cache index key, since the new title never ended up in an index
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:id/title:#{cache_hash('1/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:title:#{cache_hash('bob')}")
    IdentityCache.cache.expects(:delete).with(@blob_key)

    @record.title = 'fred'
    @record.destroy
  end

  def test_touch_will_expire_the_caches
    # Regular flow: delete data blob, delete index id, delete index id/tile
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:id/title:#{cache_hash('1/bob')}")
    IdentityCache.cache.expects(:delete).with("#{NAMESPACE}index:Record:title:#{cache_hash('bob')}")
    IdentityCache.cache.expects(:delete).with(@blob_key)

    @record.touch
  end
end
