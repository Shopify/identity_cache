require 'minitest/autorun'
require 'mocha/setup'
require 'active_record'
require 'helpers/cache'
require 'helpers/database_connection'

require File.dirname(__FILE__) + '/../lib/identity_cache'

DatabaseConnection.setup

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
    Object.send :remove_const, 'AssociatedRecord'
    Object.send :remove_const, 'Record'
  end

  def assert_nothing_raised
    yield
  end

  def assert_not_nil(*args)
    assert *args
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

    Object.send :const_set, 'Record', Class.new(ActiveRecord::Base).tap {|klass|
      klass.send :include, IdentityCache
      klass.belongs_to :record
      klass.has_many :associated_records, :order => "id DESC"
      klass.has_one :associated, :class_name => 'AssociatedRecord', :order => "id ASC"
    }
  end
end
