require "test_helper"

class FetchMultiTest < IdentityCache::TestCase
  def setup
    super
    @bob = Record.create!(:title => 'bob')
    @joe = Record.create!(:title => 'joe')
    @fred = Record.create!(:title => 'fred')
    @bob_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:1"
    @joe_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:2"
    @fred_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:3"
    @tenth_blob_key = "IDC:blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:10"
  end

  def test_fetch_multi_includes_cached_associations_in_the_database_find
    Record.send(:cache_has_many, :associated_records, :embed => true)
    Record.send(:cache_has_one, :associated)
    Record.send(:cache_belongs_to, :record)

    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil

    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)

    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).with([:associated_records, :associated]).returns(stub(:all => [@bob, @joe, @fred]))
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_includes_cached_associations_and_other_asked_for_associations_in_the_database_find
    Record.send(:cache_has_many, :associated_records, :embed => true)
    Record.send(:cache_has_one, :associated)
    Record.send(:cache_belongs_to, :record)

    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil

    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)

    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).with([:associated_records, :associated, {:record => []}]).returns(stub(:all => [@bob, @joe, @fred]))
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id, {:includes => :record})
  end

  def test_fetch_multi_batch_fetches_non_embedded_first_level_has_many_associations
    Record.send(:cache_has_many, :associated_records, :embed => false)

    child_records = []
    [@bob, @joe].each do |parent|
      3.times do |i|
        child_records << (child_record = parent.associated_records.create!(:name => i.to_s))
        AssociatedRecord.fetch(child_record.id)
      end
    end

    Record.fetch_multi(@bob.id, @joe.id) # populate the cache entries and associated children ID variables

    assert_memcache_operations(2) do
      @cached_bob, @cached_joe = Record.fetch_multi(@bob.id, @joe.id, :includes => :associated_records)
      assert_equal child_records[0..2].sort, @cached_bob.fetch_associated_records.sort
      assert_equal child_records[3..5].sort, @cached_joe.fetch_associated_records.sort
    end
  end

  def test_fetch_multi_batch_fetches_first_level_belongs_to_associations
    AssociatedRecord.send(:cache_belongs_to, :record, :embed => false)

    @bob_child  = @bob.associated_records.create!(:name => "bob child")
    @fred_child = @fred.associated_records.create!(:name => "fred child")

    # populate the cache entries and associated children ID variables
    AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id)
    Record.fetch_multi(@bob.id, @fred.id)

    assert_memcache_operations(2) do
      @cached_bob_child, @cached_fred_child = AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id, :includes => :record)
      assert_equal @bob,  @cached_bob_child.fetch_record
      assert_equal @fred, @cached_fred_child.fetch_record
    end
  end

  def test_fetch_multi_batch_fetches_first_level_associations_who_dont_include_identity_cache
    Record.send(:has_many, :not_cached_records)
    Record.send(:cache_has_many, :not_cached_records, :embed => true)

    @bob_child  = @bob.not_cached_records.create!(:name => "bob child")
    @fred_child = @fred.not_cached_records.create!(:name => "fred child")

    # populate the cache entries and associated children ID variables
    Record.fetch_multi(@bob.id, @fred.id)

    assert_memcache_operations(1) do
      @cached_bob_child, @cached_fred_child = Record.fetch_multi(@bob.id, @fred.id, :includes => :not_cached_records)
    end
  end

  def test_fetch_multi_batch_fetches_non_embedded_second_level_has_many_associations
    Record.send(:cache_has_many, :associated_records, :embed => false)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => false)

    child_records, grandchildren = setup_has_many_children_and_grandchildren(@bob, @joe)

    assert_memcache_operations(3) do
      @cached_bob, @cached_joe = Record.fetch_multi(@bob.id, @joe.id, :includes => {:associated_records => :deeply_associated_records})
      bob_children = @cached_bob.fetch_associated_records.sort
      joe_children = @cached_joe.fetch_associated_records.sort

      assert_equal grandchildren[0..2].sort,   bob_children[0].fetch_deeply_associated_records.sort
      assert_equal grandchildren[3..5].sort,   bob_children[1].fetch_deeply_associated_records.sort
      assert_equal grandchildren[6..8].sort,   bob_children[2].fetch_deeply_associated_records.sort
      assert_equal grandchildren[9..11].sort,  joe_children[0].fetch_deeply_associated_records.sort
      assert_equal grandchildren[12..14].sort, joe_children[1].fetch_deeply_associated_records.sort
      assert_equal grandchildren[15..17].sort, joe_children[2].fetch_deeply_associated_records.sort
    end
  end

  def test_fetch_multi_batch_fetches_non_embedded_second_level_belongs_to_associations
    Record.send(:cache_belongs_to, :record, :embed => false)
    AssociatedRecord.send(:cache_belongs_to, :record, :embed => false)

    @bob_child  = @bob.associated_records.create!(:name => "bob child")
    @fred_child = @fred.associated_records.create!(:name => "fred child")
    @bob.update_attribute(:record_id, @bob.id)
    @fred.update_attribute(:record_id, @fred.id)

    # populate the cache entries and associated children ID variables
    AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id)
    Record.fetch_multi(@bob.id, @fred.id)

    assert_memcache_operations(3) do
      @cached_bob_child, @cached_fred_child = AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id, :includes => {:record => :record})

      @cached_bob_parent  = @cached_bob_child.fetch_record
      @cached_fred_parent = @cached_fred_child.fetch_record
      assert_equal @bob,  @cached_bob_parent.fetch_record
      assert_equal @fred, @cached_fred_parent.fetch_record
    end
  end

  def test_fetch_multi_doesnt_batch_fetches_belongs_to_associations_if_the_foreign_key_isnt_present
    AssociatedRecord.send(:cache_belongs_to, :record, :embed => false)
    @child = AssociatedRecord.create!(:name => "bob child")
    # populate the cache entry
    AssociatedRecord.fetch_multi(@child.id)

    assert_memcache_operations(1) do
      @cached_child = AssociatedRecord.fetch_multi(@child.id, :includes => :record)
    end
  end


  def test_fetch_multi_batch_fetches_non_embedded_second_level_associations_through_embedded_first_level_has_many_associations
    Record.send(:cache_has_many, :associated_records, :embed => true)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => false)

    child_records, grandchildren = setup_has_many_children_and_grandchildren(@bob, @joe)

    assert_memcache_operations(2) do
      @cached_bob, @cached_joe = Record.fetch_multi(@bob.id, @joe.id, :includes => {:associated_records => :deeply_associated_records})
      bob_children = @cached_bob.fetch_associated_records.sort
      joe_children = @cached_joe.fetch_associated_records.sort

      assert_equal grandchildren[0..2].sort,   bob_children[0].fetch_deeply_associated_records.sort
      assert_equal grandchildren[3..5].sort,   bob_children[1].fetch_deeply_associated_records.sort
      assert_equal grandchildren[6..8].sort,   bob_children[2].fetch_deeply_associated_records.sort
      assert_equal grandchildren[9..11].sort,  joe_children[0].fetch_deeply_associated_records.sort
      assert_equal grandchildren[12..14].sort, joe_children[1].fetch_deeply_associated_records.sort
      assert_equal grandchildren[15..17].sort, joe_children[2].fetch_deeply_associated_records.sort
    end
  end

  def test_fetch_multi_batch_fetches_non_embedded_second_level_associations_through_embedded_first_level_has_one_associations
    Record.send(:cache_has_one, :associated, :embed => true)
    AssociatedRecord.send(:cache_has_many, :deeply_associated_records, :embed => false)

    @bob_child = @bob.create_associated!(:name => "bob child")
    @joe_child = @joe.create_associated!(:name => "joe child")

    grandchildren = setup_grandchildren(@bob_child, @joe_child)
    AssociatedRecord.fetch_multi(@bob_child.id, @joe_child.id)
    Record.fetch_multi(@bob.id, @joe.id)

    assert_memcache_operations(2) do
      @cached_bob, @cached_joe = Record.fetch_multi(@bob.id, @joe.id, :includes => {:associated => :deeply_associated_records})
      bob_child = @cached_bob.fetch_associated
      joe_child = @cached_joe.fetch_associated

      assert_equal grandchildren[0..2].sort,   bob_child.fetch_deeply_associated_records.sort
      assert_equal grandchildren[3..5].sort,   joe_child.fetch_deeply_associated_records.sort
    end
  end

  def test_find_batch_coerces_ids_to_primary_key_type
    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).returns(stub(:all => [@bob, @joe, @fred]))

    Record.find_batch([@bob, @joe, @fred].map(&:id).map(&:to_s))
  end

  private

  def setup_has_many_children_and_grandchildren(*parents)
    child_records = []
    grandchildren = []

    parents.each do |parent|
      3.times do |i|
        child_records << (child = parent.associated_records.create!(:name => i.to_s))
        grandchildren.concat setup_grandchildren(child)
        AssociatedRecord.fetch(child.id)
      end
    end

    Record.fetch_multi(*parents.map(&:id)) # populate the cache entries and associated children ID variables

    return child_records, grandchildren
  end

  def setup_grandchildren(*children)
    grandchildren = []
    children.each do |child|
      3.times do |j|
        grandchildren << (grandchild = child.deeply_associated_records.create!(:name => j.to_s))
        DeeplyAssociatedRecord.fetch(grandchild.id)
      end
    end
    grandchildren
  end
end
