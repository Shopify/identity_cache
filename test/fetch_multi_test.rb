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

  def test_fetch_multi_with_all_misses_publishes_notifications
    cache_response = {}
    cache_response[@bob_blob_key] = nil
    cache_response[@joe_blob_key] = nil
    cache_response[@fred_blob_key] = nil
    fetch_multi_stub(cache_response)

    events = 0
    subscriber = ActiveSupport::Notifications.subscribe('dehydration.identity_cache') do |_, _, _, _, payload|
      events += 1
      assert_equal "Item", payload[:class]
    end
    Item.fetch_multi(@bob.id, @joe.id, @fred.id)
    assert_equal 3, events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
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

  def test_fetch_multi_with_mixed_hits_and_misses_notifies
    subscriber = nil
    Item.fetch(@bob.id)

    IdentityCache.cache.with_memoization do
      Item.fetch(@fred.id)
      expected = { memoizing: true, memo_hits: 1, cache_hits: 1, cache_misses: 1 }
      events = 0
      subscriber = ActiveSupport::Notifications.subscribe('cache_fetch_multi.identity_cache') do |_, _, _, _, payload|
        events += 1
        assert payload.delete(:resolve_miss_time) > 0
        assert_equal expected, payload
      end
      Item.fetch_multi(@bob.id, @joe.id, @fred.id)
      assert_equal 1, events
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
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

  def test_fetch_multi_with_duplicate_ids_hits_backend_once_per_id
    cache_response = {
      @joe_blob_key => cache_response_for(@joe),
      @bob_blob_key => cache_response_for(@bob),
    }

    fetcher.expects(:fetch_multi).with([@joe_blob_key, @bob_blob_key]).returns(cache_response)
    result = Item.fetch_multi(@joe.id, @bob.id, @joe.id)

    assert_equal [@joe, @bob, @joe], result
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

  def test_fetch_multi_id_coercion
    assert_equal @joe.title, Item.fetch_multi(@joe.id.to_f).first.title
    @joe.update_attributes!(title: "#{@joe.title} changed")

    assert_equal @joe.title, Item.fetch_multi(@joe.id.to_f).first.title
  end

  def test_fetch_multi_raises_when_called_on_a_scope
    assert_raises(IdentityCache::UnsupportedScopeError) do
      Item.where(updated_at: nil).fetch_multi(@bob.id, @joe.id, @fred.id)
    end
  end

  def test_fetch_multi_on_derived_model_raises
    assert_raises(IdentityCache::DerivedModelError) do
      StiRecordTypeA.fetch_multi(1, 2)
    end
  end

  def test_fetch_multi_with_mixed_hits_and_misses_returns_only_readonly_records
    IdentityCache.with_fetch_read_only_records do
      cache_response = {}
      cache_response[@bob_blob_key] = cache_response_for(@bob)
      cache_response[@joe_blob_key] = nil
      cache_response[@fred_blob_key] = cache_response_for(@fred)
      fetch_multi = fetch_multi_stub(cache_response)

      response = Item.fetch_multi(@bob.id, @joe.id, @fred.id)
      assert fetch_multi.has_been_called_with?(@bob_blob_key, @joe_blob_key, @fred_blob_key)
      assert_equal [@bob, @joe, @fred], response

      assert response.all?(&:readonly?)
    end
  end

  def test_fetch_multi_with_mixed_hits_and_misses_and_responses_in_the_wrong_order_returns_readonly
    IdentityCache.with_fetch_read_only_records do
      cache_response = {}
      cache_response[@bob_blob_key] = nil
      cache_response[@joe_blob_key] = nil
      cache_response[@fred_blob_key] = cache_response_for(@fred)
      fetch_multi = fetch_multi_stub(cache_response)

      response = Item.fetch_multi(@bob.id, @joe.id, @fred.id)
      assert fetch_multi.has_been_called_with?(@bob_blob_key, @joe_blob_key, @fred_blob_key)
      assert_equal [@bob, @joe, @fred], response

      assert response.all?(&:readonly?)
    end
  end

  def test_fetch_multi_with_open_transactions_returns_non_readonly_records
    IdentityCache.with_fetch_read_only_records do
      Item.transaction do
        assert_equal IdentityCache.should_use_cache?, false
        IdentityCache.cache.expects(:fetch_multi).never
        assert Item.fetch_multi(@bob.id, @joe.id, @fred.id).none?(&:readonly?)
      end
    end
  end

  def test_fetch_multi_with_no_keys_does_not_query_when_cache_is_disabled
    Item.stubs(:should_use_cache?).returns(false)

    assert_queries(0) do
      assert_memcache_operations(0) do
        Item.fetch_multi
      end
    end
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
    { class: record.class.name, attributes: record.attributes_before_type_cast }
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
