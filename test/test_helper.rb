require 'minitest/autorun'
require 'mocha/setup'
require 'active_record'
require 'helpers/cache'
require 'helpers/database_connection'

require File.dirname(__FILE__) + '/../lib/identity_cache'

if ENV['BOXEN_HOME'].present?
  $memcached_port = 21211
  $mysql_port = 13306
else
  $memcached_port = 11211
  $mysql_port = 3306
end

DatabaseConnection.setup
ActiveSupport::Cache::Store.instrument = true

# This patches AR::MemcacheStore to notify AS::Notifications upon read_multis like the rest of rails does
class ActiveSupport::Cache::MemCacheStore
  def read_multi_with_instrumentation(*args, &block)
    instrument("read_multi", "many keys") do
      read_multi_without_instrumentation(*args, &block)
    end
  end

  alias_method_chain :read_multi, :instrumentation
end

class IdentityCache::TestCase < MiniTest::Unit::TestCase
  def setup
    DatabaseConnection.drop_tables
    DatabaseConnection.create_tables

    setup_models
  end

  def teardown
    IdentityCache.cache.clear
    ActiveSupport::DescendantsTracker.clear
    ActiveSupport::Dependencies.clear
    Object.send :remove_const, 'DeeplyAssociatedRecord'
    Object.send :remove_const, 'PolymorphicRecord'
    Object.send :remove_const, 'AssociatedRecord'
    Object.send :remove_const, 'NotCachedRecord'
    Object.send :remove_const, 'Record'
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
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    assert_equal num, counter.log.size, "#{counter.log.size} instead of #{num} queries were executed.#{counter.log.size == 0 ? '' : "\nQueries:\n#{counter.log.join("\n")}"}"
  end

  def assert_memcache_operations(num)
    counter = 0
    subscriber = ActiveSupport::Notifications.subscribe(/cache_.*\.active_support/) do |*args|
      counter += 1
    end
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    assert_equal num, counter, "#{counter} instead of #{num} memcache operations were executed."
  end

  def assert_no_queries
    assert_queries(0) do
      yield
    end
  end

  def cache_hash(key)
    CityHash.hash64(key)
  end

  private
  def setup_models
    Object.send :const_set, 'DeeplyAssociatedRecord', Class.new(ActiveRecord::Base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :associated_record
    }

    Object.send :const_set, 'AssociatedRecord', Class.new(ActiveRecord::Base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :record
      klass.has_many :deeply_associated_records, :order => "name DESC"
    }

    Object.send :const_set, 'NotCachedRecord', Class.new(ActiveRecord::Base).tap {|klass|
      klass.belongs_to :record, :touch => true
    }

    Object.send :const_set, 'PolymorphicRecord', Class.new(ActiveRecord::Base).tap {|klass|
      klass.belongs_to :owner, :polymorphic => true
    }

    Object.send :const_set, 'Record', Class.new(ActiveRecord::Base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :record
      klass.has_many :associated_records, :order => "id DESC"
      klass.has_many :not_cached_records, :order => "id DESC"
      klass.has_many :polymorphic_records, :as => 'owner'
      klass.has_one :polymorphic_record, :as => 'owner'
      klass.has_one :associated, :class_name => 'AssociatedRecord', :order => "id ASC"
    }
  end
end

class SQLCounter
  cattr_accessor :ignored_sql
  self.ignored_sql = [/^PRAGMA (?!(table_info))/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /^SHOW max_identifier_length/, /^BEGIN/, /^COMMIT/]

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
