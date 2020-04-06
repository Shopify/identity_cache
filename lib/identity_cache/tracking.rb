# frozen_string_literal: true

module IdentityCache
  module Tracking
    TrackedObject = Struct.new(:object, :includes, :caller, :accessed_associations)

    extend self

    def tracked_objects
      Thread.current[:idc_tracked_objects] ||= {}
    end

    def reset_tracked_objects
      Thread.current[:idc_tracked_objects] = {}
    end

    def track_object(object, includes)
      return unless object_tracking_enabled
      locations = caller(1, 20)
      tracked_objects[object] = TrackedObject.new(object, Array(includes), locations, Set.new)
    end

    def track_association_accessed(object, association_name)
      return unless object_tracking_enabled
      obj = self.tracked_objects[object]
      obj.accessed_associations << association_name if obj
    end

    def instrument_and_reset_tracked_objects
      tracked_objects.each do |_, to|
        ActiveSupport::Notifications.instrument('object_track.identity_cache', {
          object: to.object,
          accessed_associations: to.accessed_associations,
          caller: to.caller
        })
      end
      reset_tracked_objects
    end

    def with_object_tracking_and_instrumentation
      begin
        with_object_tracking { yield }
      ensure
        instrument_and_reset_tracked_objects
      end
    end

    def with_object_tracking(enabled: true)
      begin
        orig = object_tracking_enabled
        self.object_tracking_enabled = enabled
        yield
      ensure
        self.object_tracking_enabled = orig
      end
    end

    def skip_object_tracking
      with_object_tracking(enabled: false) { yield }
    end

    def object_tracking_enabled
      Thread.current[:object_tracking_enabled]
    end

    def object_tracking_enabled=(value)
      Thread.current[:object_tracking_enabled] = value
    end
  end
end
