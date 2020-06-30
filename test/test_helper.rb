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

    def count_queries
      counter = SQLCounter.new
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record', counter)
      yield
      counter.log.size
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def assert_queries(num = 1)
      counter = SQLCounter.new
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record', counter)
      exception = false
      yield
    rescue
      exception = true
      raise
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
      assert_equal(
        num,
        counter.log.size,
        <<~MSG.squish
          #{counter.log.size} instead of #{num} queries were executed.
          #{counter.log.empty? ? '' : "\nQueries:\n#{counter.log.join("\n")}"}
        MSG
      ) unless exception
    end

    def assert_memcache_operations(num)
      counter = CacheCounter.new
      subscriber = ActiveSupport::Notifications.subscribe(/cache_.*\.active_support/, counter)
      exception = false
      yield
    rescue
      exception = true
      raise
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
      assert_equal(
        num,
        counter.log.size,
        <<~MSG.squish
          #{counter.log.size} instead of #{num} memcache operations were executed.
          #{counter.log.empty? ? '' : "\nOperations:\n#{counter.log.join("\n")}"}
        MSG
      ) unless exception
    end

    def assert_no_queries
      assert_queries(0) do
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

class SQLCounter
  cattr_accessor :ignored_sql
  self.ignored_sql = [
    /^PRAGMA (?!(table_info))/,
    /^SELECT currval/,
    /^SELECT CAST/,
    /^SELECT @@IDENTITY/,
    /^SELECT @@ROWCOUNT/,
    /^SAVEPOINT/,
    /^ROLLBACK TO SAVEPOINT/,
    /^RELEASE SAVEPOINT/,
    /^SHOW max_identifier_length/,
    /^BEGIN/,
    /^COMMIT/,
    /^SHOW /,
  ]

  # FIXME: this needs to be refactored so specific database can add their own
  # ignored SQL.  This ignored SQL is for Oracle.
  ignored_sql.concat([
    /^select .*nextval/i,
    /^SAVEPOINT/,
    /^ROLLBACK TO/,
    /^\s*select .* from all_triggers/im,
  ])

  attr_reader :ignore
  attr_accessor :log

  def initialize(ignore = self.class.ignored_sql)
    @ignore = ignore
    @log = []
  end

  def call(_name, _start, _finish, _message_id, values)
    sql = values[:sql]

    # FIXME: this seems bad. we should probably have a better way to indicate
    # the query was cached
    return if 'CACHE' == values[:name] || ignore.any? { |x| x =~ sql }
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
