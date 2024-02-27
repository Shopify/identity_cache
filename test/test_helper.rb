# frozen_string_literal: true

require "logger"
require "minitest/autorun"
require "mocha/minitest"
require "active_record"
require "helpers/database_connection"
require "helpers/cache_connection"
require "helpers/active_record_objects"
require "helpers/mocked_cache_backend"
require "spy/integration"

require File.dirname(__FILE__) + "/../lib/identity_cache"

DatabaseConnection.setup
CacheConnection.setup

module IdentityCache
  class TestCase < Minitest::Test
    include ActiveRecordObjects
    attr_reader :backend

    HAVE_LAZY_BEGIN = ActiveRecord.gem_version >= Gem::Version.new("6.0.0")

    def setup
      ActiveRecord::Base.connection.schema_cache.clear!
      DatabaseConnection.drop_tables
      DatabaseConnection.create_tables

      IdentityCache.logger = Logger.new(nil)

      @backend = CacheConnection.backend
      IdentityCache.cache_backend = @backend

      setup_models
    end

    def teardown
      IdentityCache.cache.clear
      teardown_models
    end

    private

    def ar_query_method(connection)
      if connection.respond_to?(:internal_exec_query, true)
        :internal_exec_query
      else
        :exec_query
      end
    end

    def create(class_symbol)
      class_symbol.to_s.classify.constantize.create!
    end

    def create_list(class_symbol, count)
      count.times.map { create(class_symbol) }
    end

    def fetcher
      IdentityCache.cache.cache_fetcher
    end

    def assert_nothing_raised
      yield
    end

    def assert_not_nil(*args)
      assert(*args)
    end

    def subscribe_to_sql_queries(subscriber, all: false)
      filtering_subscriber = ->(_name, _start, _finish, _message_id, values) { subscriber.call(values.fetch(:sql)) }
      filtering_subscriber = IgnoreSchemaQueryFilter.new(filtering_subscriber) unless all
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record", filtering_subscriber)
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    def count_queries(**subscribe_opts, &block)
      count = 0
      subscribe_to_sql_queries(->(_sql) { count += 1 }, **subscribe_opts, &block)
      count
    end

    def assert_queries(num = 1, **subscribe_opts, &block)
      log = []
      ret = subscribe_to_sql_queries(->(sql) { log << sql }, **subscribe_opts, &block)

      msg = "#{log.size} instead of #{num} queries were executed."
      msg << "\nQueries:\n#{log.join("\n")}" unless log.empty?

      assert_equal(num, log.size, msg)
      ret
    end

    def assert_queries_sql(sql_queries, &block)
      log = []
      ret = subscribe_to_sql_queries(->(sql) { log << sql }, &block)
      assert_equal(sql_queries, log)
      ret
    end

    def subscribe_to_cache_operations(subscriber)
      formatting_subscriber = lambda do |name, _start, _finish, _message_id, values|
        operation = "#{name} #{values[:keys].try(:join, ", ") || values[:key]}"
        subscriber.call(operation)
      end
      subscription = ActiveSupport::Notifications.subscribe(/cache_.*\.active_support/, formatting_subscriber)
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    def assert_memcache_operations(num, &block)
      log = []
      ret = subscribe_to_cache_operations(->(operation) { log << operation }, &block)
      assert_equal(
        num,
        log.size,
        <<~MSG.squish
          #{log.size} instead of #{num} memcache operations were executed.
          #{log.empty? ? "" : "\nOperations:\n#{log.join("\n")}"}
        MSG
      )
      ret
    end

    def assert_no_queries(**subscribe_opts, &block)
      subscribe_to_sql_queries(->(sql) { raise "Unexpected SQL query: #{sql}" }, **subscribe_opts, &block)
    end

    def cache_hash(key)
      IdentityCache.memcache_hash(key)
    end

    def reflect(model, association_name)
      model.reflect_on_association(association_name)
    end
  end
end

# Based on SQLCounter in the active record test suite
class IgnoreSchemaQueryFilter
  def initialize(subscriber)
    @subscriber = subscriber
  end

  def call(name, start, finish, message_id, values)
    return if values[:cached]
    return if values[:name] == "SCHEMA"

    @subscriber.call(name, start, finish, message_id, values)
  end
end
