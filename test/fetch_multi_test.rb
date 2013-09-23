require "test_helper"

class FetchMultiTest < IdentityCache::TestCase
  NAMESPACE = IdentityCache.cache_namespace

  def setup
    super
    @bob = Record.create!(:title => 'bob')
    @joe = Record.create!(:title => 'joe')
    @fred = Record.create!(:title => 'fred')
    @bob_blob_key = "#{NAMESPACE}blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:1"
    @joe_blob_key = "#{NAMESPACE}blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:2"
    @fred_blob_key = "#{NAMESPACE}blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:3"
    @tenth_blob_key = "#{NAMESPACE}blob:Record:#{cache_hash("created_at:datetime,id:integer,record_id:integer,title:string,updated_at:datetime")}:10"
  end

  def test_fetch_multi_with_no_records
    assert_equal [], Record.fetch_multi
  end

  def test_fetch_multi_namespace
    Record.send(:include, SwitchNamespace)
    bob_blob_key, joe_blob_key, fred_blob_key = [@bob_blob_key, @joe_blob_key, @fred_blob_key].map { |k| "ns:#{k}" }
    cache_response = {}
    cache_response[bob_blob_key] = cache_response_for(@bob)
    cache_response[joe_blob_key] = cache_response_for(@joe)
    cache_response[fred_blob_key] = cache_response_for(@fred)
    IdentityCache.cache.expects(:read_multi).with(bob_blob_key, joe_blob_key, fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_all_hits
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = cache_response_for(@joe)
    cache_response[@fred_blob_key] = cache_response_for(@fred)
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_all_misses
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = cache_response_for(@fred)
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @joe_blob_key, @fred_blob_key).returns(cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_responses_in_the_wrong_order
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = cache_response_for(@fred)
    IdentityCache.cache.expects(:read_multi).with(@bob_blob_key, @fred_blob_key, @joe_blob_key).returns(cache_response)
    assert_equal [@bob, @fred, @joe], Record.fetch_multi(@bob.id, @fred.id, @joe.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_non_existant_keys_1
    populate_only_fred

    IdentityCache.cache.expects(:read_multi).with(@tenth_blob_key, @bob_blob_key, @joe_blob_key, @fred_blob_key).returns(@cache_response)
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(10, @bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_non_existant_keys_2
    populate_only_fred

    IdentityCache.cache.expects(:read_multi).with(@fred_blob_key, @bob_blob_key, @tenth_blob_key, @joe_blob_key).returns(@cache_response)
    assert_equal [@fred, @bob, @joe], Record.fetch_multi(@fred.id, @bob.id, 10, @joe.id)
  end


  def test_fetch_multi_works_with_nils
    cache_result = {1 => IdentityCache::CACHED_NIL, 2 => IdentityCache::CACHED_NIL}
    fetch_result = {1 => nil, 2 => nil}

    IdentityCache.cache.expects(:read_multi).with(1,2).times(2).returns({1 => nil, 2 => nil}, cache_result)
    IdentityCache.cache.expects(:write).with(1, IdentityCache::CACHED_NIL).once
    IdentityCache.cache.expects(:write).with(2, IdentityCache::CACHED_NIL).once

    results = IdentityCache.fetch_multi(1,2) do |keys|
      [nil, nil]
    end
    assert_equal fetch_result, results

    results = IdentityCache.fetch_multi(1,2) do |keys|
      flunk "Contents should have been fetched from cache successfully"
    end

    assert_equal fetch_result, results
  end

  def test_fetch_multi_duplicate_ids
    assert_equal [@joe, @bob, @joe], Record.fetch_multi(@joe.id, @bob.id, @joe.id)
  end

  def test_fetch_multi_with_open_transactions_hits_the_database
    Record.connection.expects(:open_transactions).at_least_once.returns(1)
    IdentityCache.cache.expects(:read_multi).never
    assert_equal [@bob, @joe, @fred], Record.fetch_multi(@bob.id, @joe.id, @fred.id)
  end

  def test_fetch_multi_with_open_transactions_returns_results_in_the_order_of_the_passed_ids
    Record.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @bob, @fred], Record.fetch_multi(@joe.id, @bob.id, @fred.id)
  end

  def test_fetch_multi_with_duplicate_ids_in_transaction_returns_results_in_the_order_of_the_passed_ids
    Record.connection.expects(:open_transactions).at_least_once.returns(1)
    assert_equal [@joe, @bob, @joe], Record.fetch_multi(@joe.id, @bob.id, @joe.id)
  end

  def test_find_batch_coerces_ids_to_primary_key_type
    mock_relation = mock("ActiveRecord::Relation")
    Record.expects(:where).returns(mock_relation)
    mock_relation.expects(:includes).returns(stub(:all => [@bob, @joe, @fred]))

    Record.find_batch([@bob, @joe, @fred].map(&:id).map(&:to_s))
  end

  def test_fetch_multi_doesnt_freeze_keys
    cache_response = {}
    cache_response[@bob_blob_key] = cache_response_for(@bob)
    cache_response[@joe_blob_key] = cache_response_for(@fred)

    IdentityCache.expects(:fetch_multi).with{ |*args| args.none?(&:frozen?) }.returns(cache_response)

    Record.fetch_multi(@bob.id, @joe.id)
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
    coder = {:class => record.class}
    record.encode_with(coder)
    coder
  end
end
