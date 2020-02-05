# frozen_string_literal: true
require "test_helper"

module IdentityCache
  class PrefetchAssociationsTest < IdentityCache::TestCase
    NAMESPACE = IdentityCache.cache_namespace

    def setup
      super
      @bob = Item.create!(title: 'bob')
      @joe = Item.create!(title: 'joe')
      @fred = Item.create!(title: 'fred')
      attr_string = "created_at:datetime,id:integer,item_id:integer,title:string,updated_at:datetime"
      @bob_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash(attr_string)}:1"
      @joe_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash(attr_string)}:2"
      @fred_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash(attr_string)}:3"
      @tenth_blob_key = "#{NAMESPACE}blob:Item:#{cache_hash(attr_string)}:10"
    end

    def test_prefetch_associations_on_fetched_records
      Item.send(:cache_belongs_to, :item)
      john = Item.create!(title: 'john')
      jim = Item.create!(title: 'jim')
      @bob.update_column(:item_id, john.id)
      @joe.update_column(:item_id, jim.id)
      items = Item.fetch_multi(@bob.id, @joe.id, @fred.id)

      spy = Spy.on(CacheKeyLoader, :load_batch).and_call_through

      prefetch(Item, :item, items)

      assert_equal(
        spy.calls.map(&:args).last,
        [{ Item.cached_primary_index => [john.id, jim.id] }]
      )
    end

    def test_prefetch_associations_on_db_records
      Item.send(:cache_has_many, :associated_records, embed: true)
      AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: :ids)

      setup_has_many_children_and_grandchildren(@bob)

      item = Item.find(@bob.id)

      assert_no_queries do
        assert_memcache_operations(1) do
          prefetch(Item, :associated_records, [item])
        end
        assert_memcache_operations(0) do
          item.fetch_associated_records.each(&:fetch_deeply_associated_record_ids)
        end
        assert_memcache_operations(1) do
          prefetch(Item, { associated_records: :deeply_associated_records }, [item])
        end
        assert_memcache_operations(0) do
          item.fetch_associated_records.each(&:fetch_deeply_associated_records)
        end
      end
    end

    def test_prefetch_associations_without_using_cache
      Item.send(:cache_has_many, :associated_records, embed: true)

      associated1 = @bob.associated_records.create!(name: 'foo')
      associated2 = @joe.associated_records.create!(name: 'bar')
      items = [@bob, @joe].map(&:reload)

      Item.transaction do
        assert_memcache_operations(0) do
          assert_queries(1) do
            prefetch(Item, :associated_records, items)
          end
          assert_no_queries do
            assert_equal [[associated1], [associated2]], items.map(&:fetch_associated_records)
          end
        end
      end
    end

    def test_prefetch_associations_cached_belongs_to
      Item.send(:cache_belongs_to, :item)
      @bob.update_attributes!(item_id: @joe.id)
      @joe.update_attributes!(item_id: @fred.id)
      @bob.fetch_item
      @joe.fetch_item
      items = [@bob, @joe].map(&:reload)

      assert_no_queries do
        assert_memcache_operations(1) do
          prefetch(Item, :item, items)
        end
        assert_memcache_operations(0) do
          items.each(&:fetch_item)
        end
        assert_memcache_operations(0) do
          prefetch(Item, :item, items)
        end
      end
    end

    def test_prefetch_associations_notifies_about_hydration
      Item.send(:cache_belongs_to, :item)
      @bob.update_attributes!(item_id: @joe.id)
      @joe.update_attributes!(item_id: @fred.id)
      @bob.fetch_item
      @joe.fetch_item
      items = [@bob, @joe].map(&:reload)
      events = 0
      subscriber = ActiveSupport::Notifications.subscribe('hydration.identity_cache') do |_, _, _, _, payload|
        events += 1
        assert_equal "Item", payload[:class]
      end
      prefetch(Item, :item, items)
      assert_equal(2, events)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    def test_prefetch_associations_with_nil_cached_belongs_to
      Item.send(:cache_belongs_to, :item)
      @bob.update_attributes!(item_id: 1234)
      assert_nil(@bob.fetch_item)

      assert_no_queries do
        assert_memcache_operations(0) do
          prefetch(Item, :item, [@bob])
        end
      end
    end

    def test_prefetch_associations_on_association
      AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: true)

      setup_has_many_children_and_grandchildren(@bob)

      associated_records = @bob.associated_records

      assert_queries(1) do
        assert_memcache_operations(1) do
          prefetch(AssociatedRecord, :deeply_associated_records, associated_records)
        end
      end
      assert_no_queries do
        assert_memcache_operations(0) do
          associated_records.each(&:fetch_deeply_associated_records)
        end
      end
    end

    def test_prefetch_associations_through_nil_cache_has_one_association
      Item.send(:cache_has_one, :associated, embed: true)
      AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: :ids)
      bob_child = @bob.create_associated!(name: "bob child")
      bob_child.deeply_associated_records.create!(name: "deep child")
      AssociatedRecord.fetch_multi(bob_child.id)
      Item.fetch_multi(@bob.id, @joe.id)

      assert_memcache_operations(2) do
        cached_bob, cached_joe = Item.fetch_multi(
          @bob.id, @joe.id, includes: { associated: :deeply_associated_records }
        )
        assert_nil cached_joe.fetch_associated
        assert_equal 'deep child', cached_bob.fetch_associated.fetch_deeply_associated_records.first.name
      end
    end

    def test_fetch_with_includes_option
      Item.send(:cache_belongs_to, :item)
      john = Item.create!(title: 'john')
      @bob.update_column(:item_id, john.id)

      spy = Spy.on(CacheKeyLoader, :load_batch).and_call_through

      assert_equal(@bob, Item.fetch(@bob.id, includes: :item))

      assert_equal(
        spy.calls.map(&:args).last,
        [{ Item.cached_primary_index => [john.id] }]
      )
    end

    def test_fetch_multi_with_includes_option
      Item.send(:cache_belongs_to, :item)
      john = Item.create!(title: 'john')
      jim = Item.create!(title: 'jim')
      @bob.update_column(:item_id, john.id)
      @joe.update_column(:item_id, jim.id)

      spy = Spy.on(CacheKeyLoader, :load_batch).and_call_through

      assert_equal([@bob, @joe, @fred], Item.fetch_multi(@bob.id, @joe.id, @fred.id, includes: :item))

      assert_equal(
        spy.calls.map(&:args).last,
        [{ Item.cached_primary_index => [john.id, jim.id] }]
      )
    end

    def test_fetch_multi_batch_fetches_non_embedded_first_level_has_many_associations
      Item.send(:cache_has_many, :associated_records, embed: :ids)

      child_records = []
      [@bob, @joe].each do |parent|
        3.times do |i|
          child_records << (child_record = parent.associated_records.create!(name: i.to_s))
          AssociatedRecord.fetch(child_record.id)
        end
      end

      Item.fetch_multi(@bob.id, @joe.id) # populate the cache entries and associated children ID variables

      assert_memcache_operations(2) do
        @cached_bob, @cached_joe = Item.fetch_multi(@bob.id, @joe.id, includes: :associated_records)
        assert_equal child_records[0..2].sort, @cached_bob.fetch_associated_records.sort
        assert_equal child_records[3..5].sort, @cached_joe.fetch_associated_records.sort
      end
    end

    def test_fetch_multi_batch_fetches_non_embedded_first_level_has_one_associations
      Item.send(:cache_has_one, :associated, embed: :id)

      child_records = []
      [@bob, @joe].each do |parent|
        child_records << (child_record = parent.create_associated(name: "child"))
        AssociatedRecord.fetch(child_record.id)
      end

      Item.fetch_multi(@bob.id, @joe.id) # populate the cache entries and associated children ID variables

      assert_memcache_operations(2) do
        @cached_bob, @cached_joe = Item.fetch_multi(@bob.id, @joe.id, includes: :associated)
        assert_equal child_records.first, @cached_bob.fetch_associated
        assert_equal child_records.second, @cached_joe.fetch_associated
      end
    end

    def test_fetch_multi_batch_fetches_first_level_belongs_to_associations
      AssociatedRecord.send(:cache_belongs_to, :item)

      @bob_child  = @bob.associated_records.create!(name: "bob child")
      @fred_child = @fred.associated_records.create!(name: "fred child")

      # populate the cache entries and associated children ID variables
      AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id)
      Item.fetch_multi(@bob.id, @fred.id)

      assert_memcache_operations(2) do
        @cached_bob_child, @cached_fred_child = AssociatedRecord.fetch_multi(
          @bob_child.id, @fred_child.id, includes: :item
        )
        assert_equal @bob,  @cached_bob_child.fetch_item
        assert_equal @fred, @cached_fred_child.fetch_item
      end
    end

    def test_fetch_multi_batch_fetches_first_level_associations_who_dont_include_identity_cache
      NotCachedRecord.include(IdentityCache::WithoutPrimaryIndex)
      Item.send(:cache_has_many, :not_cached_records, embed: true)

      @bob_child  = @bob.not_cached_records.create!(name: "bob child")
      @fred_child = @fred.not_cached_records.create!(name: "fred child")

      # populate the cache entries and associated children ID variables
      Item.fetch_multi(@bob.id, @fred.id)

      assert_memcache_operations(1) do
        @cached_bob_child, @cached_fred_child = Item.fetch_multi(@bob.id, @fred.id, includes: :not_cached_records)
      end
    end

    def test_fetch_multi_batch_fetches_non_embedded_second_level_has_many_associations
      Item.send(:cache_has_many, :associated_records, embed: :ids)
      AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: :ids)

      _child_records, grandchildren = setup_has_many_children_and_grandchildren(@bob, @joe)

      assert_memcache_operations(3) do
        @cached_bob, @cached_joe = Item.fetch_multi(
          @bob.id, @joe.id, includes: { associated_records: :deeply_associated_records }
        )
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
      Item.send(:cache_belongs_to, :item)
      AssociatedRecord.send(:cache_belongs_to, :item)

      @bob_child  = @bob.associated_records.create!(name: "bob child")
      @fred_child = @fred.associated_records.create!(name: "fred child")
      @bob.update_attribute(:item_id, @bob.id)
      @fred.update_attribute(:item_id, @fred.id)

      # populate the cache entries and associated children ID variables
      AssociatedRecord.fetch_multi(@bob_child.id, @fred_child.id)
      Item.fetch_multi(@bob.id, @fred.id)

      assert_memcache_operations(3) do
        @cached_bob_child, @cached_fred_child = AssociatedRecord.fetch_multi(
          @bob_child.id, @fred_child.id, includes: { item: :item }
        )

        @cached_bob_parent  = @cached_bob_child.fetch_item
        @cached_fred_parent = @cached_fred_child.fetch_item
        assert_equal @bob,  @cached_bob_parent.fetch_item
        assert_equal @fred, @cached_fred_parent.fetch_item
      end
    end

    def test_fetch_multi_doesnt_batch_fetches_belongs_to_associations_if_the_foreign_key_isnt_present
      AssociatedRecord.send(:cache_belongs_to, :item)
      @child = AssociatedRecord.create!(name: "bob child")
      # populate the cache entry
      AssociatedRecord.fetch_multi(@child.id)

      assert_memcache_operations(1) do
        @cached_child = AssociatedRecord.fetch_multi(@child.id, includes: :item)
      end
    end

    def test_fetch_multi_batch_fetches_non_embedded_second_level_associations_through_embedded_first_level_has_many_associations # rubocop:disable Layout/LineLength
      Item.send(:cache_has_many, :associated_records, embed: true)
      AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: :ids)

      _child_records, grandchildren = setup_has_many_children_and_grandchildren(@bob, @joe)

      assert_memcache_operations(2) do
        @cached_bob, @cached_joe = Item.fetch_multi(
          @bob.id, @joe.id, includes: { associated_records: :deeply_associated_records }
        )
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

    def test_fetch_multi_batch_fetches_non_embedded_second_level_associations_through_embedded_first_level_has_one_associations # rubocop:disable Layout/LineLength
      Item.send(:cache_has_one, :associated, embed: true)
      AssociatedRecord.send(:cache_has_many, :deeply_associated_records, embed: :ids)

      @bob_child = @bob.create_associated!(name: "bob child")
      @joe_child = @joe.create_associated!(name: "joe child")

      grandchildren = setup_grandchildren(@bob_child, @joe_child)
      AssociatedRecord.fetch_multi(@bob_child.id, @joe_child.id)
      Item.fetch_multi(@bob.id, @joe.id)

      assert_memcache_operations(2) do
        @cached_bob, @cached_joe = Item.fetch_multi(
          @bob.id, @joe.id, includes: { associated: :deeply_associated_records }
        )
        bob_child = @cached_bob.fetch_associated
        joe_child = @cached_joe.fetch_associated

        assert_equal grandchildren[0..2].sort,   bob_child.fetch_deeply_associated_records.sort
        assert_equal grandchildren[3..5].sort,   joe_child.fetch_deeply_associated_records.sort
      end
    end

    def test_load_multi_from_db_coerces_ids_to_primary_key_type
      mock_relation = mock("ActiveRecord::Relation")
      Item.expects(:where).returns(mock_relation)
      mock_relation.expects(:includes).returns(stub(to_a: [@bob, @joe, @fred]))

      Item.cached_primary_index.send(:load_multi_from_db, [@bob, @joe, @fred].map(&:id).map(&:to_s))
    end

    def test_fetch_by_index_with_includes_option
      Item.send(:cache_belongs_to, :item)
      Item.cache_index(:title)
      john = Item.create!(title: 'john')
      @bob.update_column(:item_id, john.id)

      spy = Spy.on(CacheKeyLoader, :load_batch).and_call_through

      assert_equal([@bob], Item.fetch_by_title('bob', includes: :item))

      assert_equal(
        spy.calls.map(&:args).last,
        [{ Item.cached_primary_index => [john.id] }]
      )
    end

    def test_fetch_by_unique_index_with_includes_option
      Item.send(:cache_belongs_to, :item)
      Item.cache_index(:title, unique: true)
      john = Item.create!(title: 'john')
      @bob.update_column(:item_id, john.id)

      spy = Spy.on(CacheKeyLoader, :load_batch).and_call_through

      assert_equal(@bob, Item.fetch_by_title('bob', includes: :item))

      assert_equal(
        spy.calls.map(&:args).last,
        [{ Item.cached_primary_index => [john.id] }]
      )
    end

    def test_prefetch_associations
      AssociatedRecord.send(:cache_belongs_to, :item)

      chunky_bacon = Item.create!(title: "Chunky Bacon")
      record = AssociatedRecord.create!

      record.update_column(:item_id, chunky_bacon.id)

      assert_memcache_operations(1) do
        AssociatedRecord.prefetch_associations(:item, [record])
      end

      assert_no_queries do
        assert_equal(chunky_bacon, record.fetch_item)
      end
    end

    def test_prefetch_batching
      AssociatedRecord.send(:cache_belongs_to, :item)
      AssociatedRecord.send(:cache_has_one, :deeply_associated, embed: :id)
      AssociatedRecord.send(:cache_has_many, :related_items, embed: :ids)
      DeeplyAssociatedRecord.send(:cache_belongs_to, :item)
      RelatedItem.send(:cache_belongs_to, :item)
      Item.send(:cache_has_one, :associated, embed: :id)

      rocket_shoes  = Item.create!(title: "Rocket Shoes")
      invisible_ink = Item.create!(title: "Invisible Ink")
      ray_gun       = Item.create!(title: "Ray Gun", associated: AssociatedRecord.create!)

      record = AssociatedRecord.create!(
        item: rocket_shoes,
        deeply_associated: DeeplyAssociatedRecord.create!(
          item: invisible_ink
        ),
        related_items: [
          RelatedItem.create!(
            item: ray_gun
          ),
        ]
      )

      record.reload

      assert_memcache_operations(4) do
        prefetch(
          AssociatedRecord,
          [
            :item,
            { deeply_associated: :item },
            { related_items: { item: :associated } },
          ],
          [record]
        )
      end

      assert_no_queries do
        assert_equal(
          rocket_shoes, record.fetch_item
        )
        assert_equal(
          invisible_ink,
          record.fetch_deeply_associated.fetch_item
        )
        assert_equal(
          ray_gun,
          record.fetch_related_items.first.fetch_item
        )
        assert_equal(
          ray_gun.associated,
          record.fetch_related_items.first.fetch_item.fetch_associated
        )
      end
    end

    private

    def prefetch(klass, includes, records)
      Cached::Prefetcher.prefetch(klass, includes, records)
    end

    def setup_has_many_children_and_grandchildren(*parents)
      child_records = []
      grandchildren = []

      parents.each do |parent|
        3.times do |i|
          child_records << (child = parent.associated_records.create!(name: i.to_s))
          grandchildren.concat(setup_grandchildren(child))
          AssociatedRecord.fetch(child.id)
        end
      end

      Item.fetch_multi(*parents.map(&:id)) # populate the cache entries and associated children ID variables

      [child_records, grandchildren]
    end

    def setup_grandchildren(*children)
      grandchildren = []
      children.each do |child|
        3.times do |j|
          grandchildren << (grandchild = child.deeply_associated_records.create!(name: j.to_s))
          DeeplyAssociatedRecord.fetch(grandchild.id)
        end
      end
      grandchildren
    end
  end
end
