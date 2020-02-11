# frozen_string_literal: true
require "test_helper"

module IdentityCache
  module Cached
    class AssociationTest < IdentityCache::TestCase
      def setup
        super
        @reflection = reflect(AssociatedRecord, :item)
        @association = Association.new(:item, reflection: @reflection)
      end

      attr_reader :reflection, :association

      def test_name
        assert_equal(:item, association.name)
      end

      def test_inverse_name
        reflection = reflect(Item, :associated_records)
        association = Association.new(:associated_records, reflection: reflection)

        assert_equal(:item, association.inverse_name)
      end

      def test_reflection
        assert_same(reflection, association.reflection)
      end

      def test_cached_accessor_name
        assert_equal(:fetch_item, association.cached_accessor_name)
      end
    end
  end
end
