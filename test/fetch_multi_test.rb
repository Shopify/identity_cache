require "test_helper"

class FetchMultiTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache.cache_namespace

  def setup
    super
    @bob = Item.create!(:title => 'bob')
    @joe = Item.create!(:title => 'joe')
    @fred = Item.create!(:title => 'fred')
    @bob_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:1"
    @joe_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:2"
    @fred_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:3"
    @tenth_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash("created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime")}:10"
  end

  def test_fetch_multi_with_no_records
    assert_equal [], Item.fetch_multi
  end

  def test_fetch_multi_namespace
    Item.send(:include, SwitchNamespace)
    bob_blob_key, joe_blob_key, fred_blob_key = [@bob_blob_key, @joe_blob_key, @fred_blob_key].map { |k| "ns:#{k}" }
    cache_response = {}
    cache_response[bob_blob_key] = cache_response_for(@bob)
    cache_response[joe_blob_key] = cache_response_for(@joe)
    cache_response[fred_blob_key] = cache_response_for(@fred)
    IdentityCache.cache.expects(:fetch_multi).with(bob_blob_key, joe_blob_key, fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_all_hits
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = cache_response_for(@joe)
    cache_response[@fred_blob_key] = cache_response_for(@fred)
    IdentityCache.cache.expects(:fetch_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_all_misses
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil
    fetch_multi = fetch_multi_stub(cache_response)
    assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
    assert fetch_multi.has_been_called_with?(@bob_blob_key, @joe_blob_key, @fred_blob_key)
  end

  def test_fetch_multi_with_mixed_hits_and_misses
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = cache_response_for(@fred)
    fetch_multi = fetch_multi_stub(cache_response)
    assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
    assert fetch_multi.has_been_called_with?(@bob_blob_key, @joe_blob_key, @fred_blob_key)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_responses_in_the_wrong_order
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = cache_response_for(@fred)
    fetch_multi = fetch_multi_stub(cache_response)
    assert_equal [@bob, @fred, @joe], Item.fetch_multi(@bob.id, @fred.id, @joe.id)
    assert fetch_multi.has_been_called_with?(@bob_blob_key, @fred_blob_key, @joe_blob_key)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_non_existant_keys_1
    populate_only_fred

    fetch_multi = fetch_multi_stub(@cache_response)
    assert_equal [@bob, @joe, @fred], Item.fetch_multi(10, @bob.id, @joe.id, @fred.id)
    assert fetch_multi.has_been_called_with?(@tenth_blob_key, @bob_blob_key, @joe_blob_key, @fred_blob_key)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_non_existant_keys_2
    populate_only_fred

    fetch_multi = fetch_multi_stub(@cache_response)
    assert_equal [@fred, @bob, @joe], Item.fetch_multi(@fred.id, @bob.id, 10, @joe.id)
    assert fetch_multi.has_been_called_with?(@fred_blob_key, @bob_blob_key, @tenth_blob_key, @joe_blob_key)
  end


  def test_fetch_multi_works_with_nils
    cache_result = {1 => IdentityCache::CACHED_NIL, 2 => IdentityCache::CACHED_NIL}
    fetch_result = {1 => nil, 2 => nil}

    fetcher.expects(:cas_multi).with([1, 2]).twice.returns(nil, cache_result)
    fetcher.expects(:add).with(1, IdentityCache::CACHED_NIL).once
    fetcher.expects(:add).with(2, IdentityCache::CACHED_NIL).once

    results = IdentityCache.fetch_multi(1,2) do |keys|
      [nil, nil]
    end
    assert_equal fetch_result, results

    results = IdentityCache.fetch_multi(1,2) do |keys|
      flunk "Contents should have been fetched from cache successfully"
    end

    assert_equal fetch_result, results
  end

  def test_fetch_multi_works_with_blanks
    cache_result = {1 => false, 2 => '   '}

    fetcher.expects(:fetch_multi).with([1,2]).returns(cache_result)

    results = IdentityCache.fetch_multi(1,2) do |keys|
      flunk "Contents should have been fetched from cache successfully"
    end

    assert_equal cache_result, results
  end

  def test_fetch_multi_duplicate_ids
    assert_equal [@joe, @bob, @joe], Item.fetch_multi(@joe.id, @bob.id, @joe.id)
  end

  def test_fetch_multi_with_open_transactions_hits_the_database
    Item.connection.expects(:open_transactions).at_least_once.returns(1)
    fetcher.expects(:fetch_multi).never
    assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_open_transactions_returns_results_in_the_order_of_the_passed_ids
    Item.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @bob, @fred], Item.fetch_multi(@joe.id, @bob.id, @fred.id)
  end

  def test_fetch_multi_with_open_transactions_should_compacts_returned_array
    Item.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @fred], Item.fetch_multi(@joe.id, 0, @fred.id)
  end

  def test_fetch_multi_with_duplicate_ids_in_transaction_returns_results_in_the_order_of_the_passed_ids
    Item.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @bob, @joe], Item.fetch_multi(@joe.id, @bob.id, @joe.id)
  end

  def test_find_batch_coerces_ids_to_primary_key_type
    mock_relation = mock("ActiveRecord::Relation")
    Item.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).returns(stub(:to_a => [@bob, @joe, @fred]))

    Item.send(:find_batch, [@bob, @joe, @fred].map(&:id).map(&:to_s))
  end

  def test_fetch_multi_doesnt_freeze_keys
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = cache_response_for(@fred)

    IdentityCache.expects(:fetch_multi).with{ |*args| args.none?(&:frozen?) }.returns(cache_response)

    Item.fetch_multi(@bob.id, @joe.id)
  end

  def test_fetch_multi_array
    assert_equal [@joe, @bob], Item.fetch_multi([@joe.id, @bob.id])
  end

  def test_fetch_multi_reads_in_batches
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = cache_response_for(@joe)

    with_batch_size 1 do
      fetcher.expects(:fetch_multi).with([@bob_blob_key]).returns(cache_response).once
      fetcher.expects(:fetch_multi).with([@joe_blob_key]).returns(cache_response).once
      assert_equal [@bob, @joe], Item.fetch_multi(@bob.id, @joe.id)
    end
  end

  def test_fetch_multi_max_stack_level
    cache_response = { @fred_blob_key => cache_response_for(@fred) }
    fetcher.stubs(:fetch_multi).returns(cache_response)
    assert_nothing_raised { Item.fetch_multi([@fred.id] * 200_000) }
  end

  def test_fetch_multi_with_non_id_primary_key
    fixture = KeyedRecord.create!(:value => "a") { |r| r.hashed_key = 123 }
    assert_equal [fixture], KeyedRecord.fetch_multi(123, 456)
  end

  def test_fetch_multi_after_expiring_a_record
    Item.fetch_multi(@joe.id, @fred.id)
    @bob.send(:expire_cache)
    assert_equal IdentityCache::DELETED, backend.read(@bob.primary_cache_index_key)

    add = Spy.on(IdentityCache.cache.cache_fetcher, :add).and_call_through

    assert_equal [@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id)
    refute add.has_been_called?
    assert_equal cache_response_for(Item.find(@bob.id)), backend.read(@bob.primary_cache_index_key)
  end

  private

  def populate_only_fred
    @cache_response = {}
    @cache_response[@bob_blob_key] = nil
    @cache_response[@joe_blob_key] = nil
    @cache_response[@tenth_blob_key] = nil
    @cache_response[@fred_blob_key] = cache_response_for(@fred)
  end

  def cache_response_for(record)
    coder = {'class' => record.class.name}
    record.encode_with(coder)
    coder
  end

  def with_batch_size(size)
    previous_batch_size = IdentityCache::BATCH_SIZE
    IdentityCache.send(:remove_const, :BATCH_SIZE)
    IdentityCache.const_set(:BATCH_SIZE, size)
    yield
  ensure
    IdentityCache.send(:remove_const, :BATCH_SIZE)
    IdentityCache.const_set(:BATCH_SIZE, previous_batch_size)
  end

  def fetch_multi_stub(cache_response)
    Spy.on(IdentityCache.cache, :fetch_multi).and_return do |*args, &block|
      nil_keys = cache_response.select {|_, v| v.nil? }.keys
      cache_response.merge(Hash[nil_keys.zip(block.call(nil_keys))])
    end
  end
end
