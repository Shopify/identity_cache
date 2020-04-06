# frozen_string_literal: true
require "test_helper"

class SaveTest < IdentityCache::TestCase
  def setup
    super
    Item.cache_index(:title, unique: true)
    Item.cache_has_many(:normalized_associated_records, embed: true)

    @record = Item.create(title: 'bob')
    @record.normalized_associated_records.create!
  end

  def test_fetch_index_tracks_object_no_accessed_associations
    fill_cache

    captured = 0
    subscriber = ActiveSupport::Notifications.subscribe('object_track.identity_cache') do |_, _, _, _, payload|
      captured += 1
      assert_same_record(@record, payload[:object])
      assert_equal [].to_set, payload[:accessed_associations]
      assert_kind_of Array, payload[:caller]
    end

    IdentityCache::Tracking.with_object_tracking_and_instrumentation do
      Item.fetch_by_title('bob')
    end
    assert_equal 1, captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_fetch_index_tracks_object_with_accessed_associations
    fill_cache

    captured = 0
    subscriber = ActiveSupport::Notifications.subscribe('object_track.identity_cache') do |_, _, _, _, payload|
      captured += 1
      assert_same_record(@record, payload[:object])
      assert_equal [:normalized_associated_records].to_set, payload[:accessed_associations]
      assert_kind_of Array, payload[:caller]
    end

    IdentityCache::Tracking.with_object_tracking_and_instrumentation do
      item = Item.fetch_by_title('bob')
      item.fetch_normalized_associated_records
    end
    assert_equal 1, captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end


  def test_fetch_tracks_object_no_accessed_associations
    fill_cache

    captured = 0
    subscriber = ActiveSupport::Notifications.subscribe('object_track.identity_cache') do |_, _, _, _, payload|
      captured += 1
      assert_same_record(@record, payload[:object])
      assert_equal [].to_set, payload[:accessed_associations]
      assert_kind_of Array, payload[:caller]
    end

    IdentityCache::Tracking.with_object_tracking_and_instrumentation do
      item = Item.fetch(@record.id)
    end
    assert_equal 1, captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_fetch_tracks_object_with_accessed_associations
    fill_cache

    captured = 0
    subscriber = ActiveSupport::Notifications.subscribe('object_track.identity_cache') do |_, _, _, _, payload|
      captured += 1
      assert_same_record(@record, payload[:object])
      assert_equal [:normalized_associated_records].to_set, payload[:accessed_associations]
      assert_kind_of Array, payload[:caller]
    end

    IdentityCache::Tracking.with_object_tracking_and_instrumentation do
      item = Item.fetch(@record.id)
      item.fetch_normalized_associated_records
    end
    assert_equal 1, captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def test_does_not_track_objects_unless_enabled
    fill_cache

    subscriber = ActiveSupport::Notifications.subscribe('object_track.identity_cache') do |_, _, _, _, payload|
      refute
    end

    item = Item.fetch_by_title('bob')
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  private

  def fill_cache
    item = Item.fetch_by_title('bob')
    assert item
    item.fetch_normalized_associated_records
  end

  def assert_same_record(expected, actual)
    assert_equal expected.id, actual.id
  end
end
