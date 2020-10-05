# frozen_string_literal: true
require 'logger'
require 'minitest/autorun'
require 'mocha/setup'
require 'active_record'
require 'helpers/database_connection'
require 'helpers/cache_connection'
require 'helpers/active_record_objects'
require 'spy/integration'

require File.dirname(__FILE__) + '/../lib/identity_cache'

DatabaseConnection.setup
CacheConnection.setup

MiniTest::Test = MiniTest::Unit::TestCase unless defined?(MiniTest::Test)
module IdentityCache
  class TestCase < Minitest::Test
    include ActiveRecordObjects
    attr_reader :backend

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

    def count_queries(**subscribe_opts)
      counter = SQLCounter.new(**subscribe_opts)
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record', counter)
      yield
      counter.log.size
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def assert_queries(num = 1, **subscribe_opts)
      counter = SQLCounter.new(**subscribe_opts)
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record', counter)
      ret = yield
      assert_equal(
        num,
        counter.log.size,
        <<~MSG.squish
          #{counter.log.size} instead of #{num} queries were executed.
          #{counter.log.empty? ? '' : "\nQueries:\n#{counter.log.join("\n")}"}
        MSG
      )
      ret
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def assert_memcache_operations(num)
      counter = CacheCounter.new
      subscriber = ActiveSupport::Notifications.subscribe(/cache_.*\.active_support/, counter)
      ret = yield
      assert_equal(
        num,
        counter.log.size,
        <<~MSG.squish
          #{counter.log.size} instead of #{num} memcache operations were executed.
          #{counter.log.empty? ? '' : "\nOperations:\n#{counter.log.join("\n")}"}
        MSG
      )
      ret
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def assert_no_queries(**subscribe_opts)
      assert_queries(0, **subscribe_opts) do
        yield
      end
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
class SQLCounter
  IGNORED_SQL = [
    /^SAVEPOINT/,
    /^ROLLBACK TO/,
    /^RELEASE SAVEPOINT/,
    /^BEGIN/,
    /^COMMIT/,
  ]

  attr_accessor :log, :all

  def initialize(all: false)
    @log = []
    @all = all
  end

  def call(_name, _start, _finish, _message_id, values)
    sql = values[:sql]
    unless all
      return if values[:cached]
      return if (values[:name] == 'SCHEMA' || IGNORED_SQL.any? { |p| p.match?(sql) })
    end
    log << sql
  end
end

class CacheCounter
  attr_accessor :log

  def initialize
    @log = []
  end

  def call(name, _start, _finish, _message_id, values)
    log << "#{name} #{(values[:keys].try(:join, ', ') || values[:key])}"
  end
end
