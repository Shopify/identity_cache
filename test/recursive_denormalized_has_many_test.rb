require "test_helper"

class RecursiveDenormalizedHasManyTest < IdentityCache::TestCase
  def setup
    super
    AssociatedRecord.cache_has_many :deeply_associated_records, :embed => true
    Item.cache_has_many :associated_records, :embed => true
    Item.cache_has_one :associated

    @record = Item.new(:title => 'foo')

    @associated_record = AssociatedRecord.new(:name => 'bar')
    @record.associated_records << AssociatedRecord.new(:name => 'baz')
    @record.associated_records << @associated_record

    @deeply_associated_record = DeeplyAssociatedRecord.new(:name => "corge")
    @associated_record.deeply_associated_records << @deeply_associated_record
    @associated_record.deeply_associated_records << DeeplyAssociatedRecord.new(:name => "qux")

    @record.save
    @record.reload
    @associated_record.reload
  end

  def test_cache_fetch_includes
    assert_equal [{:associated_records => [:deeply_associated_records]}, :associated => [:deeply_associated_records]], Item.send(:cache_fetch_includes)
  end

  def test_uncached_record_from_the_db_will_use_normal_association_for_deeply_associated_records
    expected = @associated_record.deeply_associated_records
    record_from_db = Item.find(@record.id)
    assert_equal expected, record_from_db.fetch_associated_records[0].fetch_deeply_associated_records
  end

  def test_on_cache_miss_record_should_embed_associated_objects_and_return
    record_from_cache_miss = Item.fetch(@record.id)
    expected = @associated_record.deeply_associated_records

    child_record_from_cache_miss = record_from_cache_miss.fetch_associated_records[0]
    assert_equal @associated_record, child_record_from_cache_miss
    assert_equal expected, child_record_from_cache_miss.fetch_deeply_associated_records
  end

  def test_on_cache_hit_record_should_return_embed_associated_objects
    Item.fetch(@record.id) # warm cache
    expected = @associated_record.deeply_associated_records

    Item.any_instance.expects(:associated_records).never
    AssociatedRecord.any_instance.expects(:deeply_associated_records).never

    record_from_cache_hit = Item.fetch(@record.id)
    child_record_from_cache_hit = record_from_cache_hit.fetch_associated_records[0]
    assert_equal @associated_record, child_record_from_cache_hit
    assert_equal expected, child_record_from_cache_hit.fetch_deeply_associated_records
  end

  def test_on_cache_miss_child_record_fetch_should_include_nested_associations_to_avoid_n_plus_ones
    assert_queries(5) do
      # one for the top level record
      # one for the mid level has_many association
      # one for the mid level has_one association
      # one for the deep level level has_many on the mid level has_many association
      # one for the deep level level has_many on the mid level has_one association
      Item.fetch(@record.id)
    end
  end

  def test_saving_child_record_should_expire_parent_record
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key)
    if AssociatedRecord.primary_cache_index_enabled
      IdentityCache.cache.expects(:delete).with(@associated_record.primary_cache_index_key)
    else
      IdentityCache.cache.expects(:delete).with(@associated_record.primary_cache_index_key).never
    end
    @associated_record.name = 'different'
    @associated_record.save!
  end

  def test_saving_grand_child_record_should_expire_parent_record
    IdentityCache.cache.expects(:delete).with(@record.primary_cache_index_key)
    if AssociatedRecord.primary_cache_index_enabled
      IdentityCache.cache.expects(:delete).with(@associated_record.primary_cache_index_key)
    else
      IdentityCache.cache.expects(:delete).with(@associated_record.primary_cache_index_key).never
    end
    IdentityCache.cache.expects(:delete).with(@deeply_associated_record.primary_cache_index_key)
    @deeply_associated_record.name = 'different'
    @deeply_associated_record.save!
  end

end

class RecursiveNormalizedHasManyTest < IdentityCache::TestCase
  def setup
    super
    AssociatedRecord.cache_has_many :deeply_associated_records, :embed => true
    Item.cache_has_many :associated_records, :embed => :ids

    @record = Item.new(:title => 'foo')
    @record.save
    @record.reload
  end

  def test_cache_repopulation_should_not_fetch_non_embedded_associations
    Item.any_instance.expects(:fetch_associated_records).never
    Item.fetch(@record.id) # cache miss
  end
end

class DisabledPrimaryIndexTest < RecursiveDenormalizedHasManyTest
  def setup
    super
    AssociatedRecord.disable_primary_cache_index
  end
end
