require 'test_helper'

class MissingConstantTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache::CacheKeyGeneration::DEFAULT_NAMESPACE

  def setup
    super

    Item.cache_index :id, :title, unique: true
    Item.cache_has_many :associated_records, embed: true

    @record = Item.create(id: 1, title: 'test')
    @record.associated_records << AssociatedRecord.new(name: 'test123')
    @record.save!

    @blob_key = "#{NAMESPACE}blob:Item:#{item_hash}:1"
    @cached_value = {
      class: @record.class.name,
      attributes: @record.attributes_before_type_cast,
      associations: {
        associated_records: [{
          class: 'InvalidAssociation',
          attributes: { a: 1, b: 'c' },
        }],
      },
    }
  end

  def test_invalid_constants_are_handled_as_misses_when_fetching_single_records
    blob_key = "#{NAMESPACE}blob:Item:#{item_hash}:1"

    IdentityCache.cache.expects(:fetch).with(blob_key).returns(@cached_value)
    IdentityCache.cache.expects(:delete).with(blob_key)

    assert_queries(2) do
      record = Item.fetch(1)
      assert_equal ['test123'], record.fetch_associated_records.map(&:name)
    end
  end

  def test_invalid_constants_are_handled_as_misses_when_fetching_multiple_records
    Item.create(id: 2, title: 'test2')

    blob_keys = [1, 2, 3].map { |id| "#{NAMESPACE}blob:Item:#{item_hash}:#{id}" }
    blob_map = blob_keys.first(2).map { |key| [key, @cached_value] }.to_h

    IdentityCache.cache.expects(:fetch_multi).with(*blob_keys).returns(blob_map)

    blob_keys.each do |key|
      IdentityCache.cache.expects(:delete).with(key)
    end

    assert_queries(2) do
      records = Item.fetch_multi(1, 2, 3)
      assert_equal 2, records.size
      assert_equal ['test123'], records.flat_map(&:fetch_associated_records).map(&:name)
    end
  end

  def test_unknown_errors_are_not_handled
    IdentityCache.cache.expects(:fetch).raises(StandardError)
    assert_raises(StandardError) { Item.fetch(1) }
  end

  private

  def item_hash
    association_hash = cache_hash('id:integer,item_id:integer,item_two_id:integer,name:string')

    cache_hash(
      'created_at:datetime,id:integer,item_id:integer,title:string,' \
      "updated_at:datetime,associated_records:(#{association_hash})"
    )
  end
end
