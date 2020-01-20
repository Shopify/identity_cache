# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module LoadStrategy
    class MultiLoadRequestTest < IdentityCache::TestCase
      def test_db_keys
        multi_load_request = MultiLoadRequest.new([
          LoadRequest.new([1], proc {}),
          LoadRequest.new([2], proc {}),
          LoadRequest.new([3], proc {}),
        ])

        assert_equal [1, 2, 3], multi_load_request.db_keys
      end

      def test_after_load
        load_requests = 3.times.map do |n|
          id     = n.next
          letter = ('a'..'z').to_a[n].to_sym
          callback = proc {}
          callback.expects(:call).with(id => letter)
          LoadRequest.new([id], callback)
        end
        multi_load_request = MultiLoadRequest.new(load_requests)

        multi_load_request.after_load({ 1 => :a, 2 => :b, 3 => :c })
      end
    end
  end
end
