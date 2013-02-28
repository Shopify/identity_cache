require "test_helper"

class ExpirationTest < IdentityCache::TestCase
  def setup
    super
    @record = Record.new
    @record.id = 1
    @record.title = 'bob'
    @cache_key = "IDC:index:Record:title:#{cache_hash(@record.title)}"
  end

  def test_unique_index_caches_nil
    Record.cache_index [:title], :unique => true
    assert_equal nil, Record.fetch_by_title('bob')
    assert_equal IdentityCache::CACHED_NIL, IdentityCache.cache.read(@cache_key)
  end

  def test_unique_index_expired_by_new_record
    Record.cache_index [:title], :unique => true
    IdentityCache.cache.write(@cache_key, IdentityCache::CACHED_NIL)
    @record.save!
    assert_equal nil, IdentityCache.cache.read(@cache_key)
  end

  def test_unique_index_filled_on_fetch_by
    Record.cache_index [:title], :unique => true
    @record.save!
    assert_equal @record, Record.fetch_by_title('bob')
    assert_equal @record.id, IdentityCache.cache.read(@cache_key)
  end

  def test_unique_index_expired_by_updated_record
    Record.cache_index [:title], :unique => true
    @record.save!
    IdentityCache.cache.write(@cache_key, @record.id)

    @record.title = 'robert'
    new_cache_key = "IDC:index:Record:title:#{cache_hash(@record.title)}"
    IdentityCache.cache.write(new_cache_key, IdentityCache::CACHED_NIL)
    @record.save!
    assert_equal nil, IdentityCache.cache.read(@cache_key)
    assert_equal nil, IdentityCache.cache.read(new_cache_key)
  end


  def test_non_unique_index_caches_empty_result
    Record.cache_index [:title]
    assert_equal [], Record.fetch_by_title('bob')
    assert_equal [], IdentityCache.cache.read(@cache_key)
  end

  def test_non_unique_index_expired_by_new_record
    Record.cache_index [:title]
    IdentityCache.cache.write(@cache_key, [])
    @record.save!
    assert_equal nil, IdentityCache.cache.read(@cache_key)
  end

  def test_non_unique_index_filled_on_fetch_by
    Record.cache_index [:title]
    @record.save!
    assert_equal [@record], Record.fetch_by_title('bob')
    assert_equal [@record.id], IdentityCache.cache.read(@cache_key)
  end

  def test_non_unique_index_fetches_multiple_records
    Record.cache_index [:title]
    @record.save!
    record2 = Record.create(:id => 2, :title => 'bob')

    assert_equal [@record, record2], Record.fetch_by_title('bob')
    assert_equal [1, 2], IdentityCache.cache.read(@cache_key)
  end

  def test_non_unique_index_expired_by_updating_record
    Record.cache_index [:title]
    @record.save!
    IdentityCache.cache.write(@cache_key, [@record.id])

    @record.title = 'robert'
    new_cache_key = "IDC:index:Record:title:#{cache_hash(@record.title)}"
    IdentityCache.cache.write(new_cache_key, [])
    @record.save!
    assert_equal nil, IdentityCache.cache.read(@cache_key)
    assert_equal nil, IdentityCache.cache.read(new_cache_key)
  end

  def test_non_unique_index_expired_by_destroying_record
    Record.cache_index [:title]
    @record.save!
    IdentityCache.cache.write(@cache_key, [@record.id])
    @record.destroy
    assert_equal nil, IdentityCache.cache.read(@cache_key)
  end

end
