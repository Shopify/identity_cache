require 'logger'
require 'minitest/autorun'
require 'mocha/setup'
require 'active_record'
require 'helpers/database_connection'
require 'helpers/active_record_objects'
require 'spy/integration'
require 'memcached_store'
require 'active_support/cache/memcached_store'

require File.dirname(__FILE__) + '/../lib/identity_cache'

DatabaseConnection.setup
ActiveSupport::Cache::Store.instrument = true if ActiveSupport::Cache::Store.respond_to?(:instrument=)

# This patches AR::MemcacheStore to notify AS::Notifications upon read_multis like the rest of rails does
class ActiveSupport::Cache::MemcachedStore
  def read_multi_with_instrumentation(*args, &block)
    instrument("read_multi", "MULTI", {:keys => args}) do
      read_multi_without_instrumentation(*args, &block)
    end
  end

  alias_method_chain :read_multi, :instrumentation
end

MiniTest::Test = MiniTest::Unit::TestCase unless defined?(MiniTest::Test)
class IdentityCache::TestCase < Minitest::Test
  include ActiveRecordObjects
  attr_reader :backend

  def setup
    if ActiveRecord::Base.respond_to?(:raise_in_transactional_callbacks=)
      ActiveRecord::Base.raise_in_transactional_callbacks = true
    end

    DatabaseConnection.drop_tables
    DatabaseConnection.create_tables

    IdentityCache.logger = Logger.new(nil)
    IdentityCache.cache_backend = @backend = ActiveSupport::Cache::MemcachedStore.new("localhost:11211", :support_cas => true)

    setup_models
  end

  def teardown
    IdentityCache.cache.clear
    teardown_models
  end

  private

  def fetcher
    IdentityCache.cache.cache_fetcher
  end

  def assert_nothing_raised
    yield
  end

  def assert_not_nil(*args)
    assert *args
  end

  def assert_queries(num = 1)
    counter = SQLCounter.new
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record', counter)
    exception = false
    yield
  rescue => e
    exception = true
    raise
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    assert_equal num, counter.log.size, "#{counter.log.size} instead of #{num} queries were executed.#{counter.log.size == 0 ? '' : "\nQueries:\n#{counter.log.join("\n")}"}" unless exception
  end

  def assert_memcache_operations(num)
    counter = CacheCounter.new
    subscriber = ActiveSupport::Notifications.subscribe(/cache_.*\.active_support/, counter)
    exception = false
    yield
  rescue => e
    exception = true
    raise
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    assert_equal num, counter.log.size, "#{counter.log.size} instead of #{num} memcache operations were executed. #{counter.log.size == 0 ? '' : "\nOperations:\n#{counter.log.join("\n")}"}" unless exception
  end

  def assert_no_queries
    assert_queries(0) do
      yield
    end
  end

  def cache_hash(key)
    IdentityCache.memcache_hash(key)
  end
end

class SQLCounter
  cattr_accessor :ignored_sql
  self.ignored_sql = [/^PRAGMA (?!(table_info))/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /^SHOW max_identifier_length/, /^BEGIN/, /^COMMIT/, /^SHOW /]

  # FIXME: this needs to be refactored so specific database can add their own
  # ignored SQL.  This ignored SQL is for Oracle.
  ignored_sql.concat [/^select .*nextval/i, /^SAVEPOINT/, /^ROLLBACK TO/, /^\s*select .* from all_triggers/im]

  attr_reader :ignore
  attr_accessor :log

  def initialize(ignore = self.class.ignored_sql)
    @ignore   = ignore
    @log = []
  end

  def call(name, start, finish, message_id, values)
    sql = values[:sql]

    # FIXME: this seems bad. we should probably have a better way to indicate
    # the query was cached
    return if 'CACHE' == values[:name] || ignore.any? { |x| x =~ sql }
    self.log << sql
  end
end

class CacheCounter
  attr_accessor :log

  def initialize()
    @log = []
  end

  def call(name, start, finish, message_id, values)
    self.log << "#{name} #{(values[:keys].try(:join, ', ') || values[:key])}"
  end
end
