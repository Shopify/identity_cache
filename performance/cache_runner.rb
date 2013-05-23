$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require 'active_record'
require 'active_support/core_ext'
require 'active_support/cache'
require 'identity_cache'
require 'memcache'
require 'debugger'

if ENV['BOXEN_HOME'].present?
  $memcached_port = 21211
  $mysql_port = 13306
else
  $memcached_port = 11211
  $mysql_port = 3306
end

require File.dirname(__FILE__) + '/../test/helpers/active_record_objects'
require File.dirname(__FILE__) + '/../test/helpers/database_connection'
require File.dirname(__FILE__) + '/../test/helpers/cache'

class FakeColumn
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def type
    :integer
  end
  def default
    0
  end
  def type_cast_code(arg)
    "1"
  end

end

class FakeRecord < ActiveRecord::Base
  attr_accessor :id

  def self.find_by_id(id, args = {})
    ret = Record.new
    ret.id = id
    return ret
  end

  def self.find(id, args = {})
    find_by_id(id, args)
  end

  def self.columns
    ['field1', 'field2', 'field3'].map { |f| FakeColumn.new(f) }
  end
end

class CacheRunner
  include ActiveRecordObjects
  include DatabaseConnection

  def initialize(count)
    @count = count
  end

  def setup
    DatabaseConnection.setup
    DatabaseConnection.drop_tables
    DatabaseConnection.create_tables
    setup_models(FakeRecord)
  end

  def prepare
  end

  def finish
    teardown_models
    DatabaseConnection.drop_tables
  end
end

class FindRunner < CacheRunner
  def run
    i = 0
    @count.times do
      ::Record.find(i)
      i+=1
    end
  end
end

class FetchMissRunner < CacheRunner
  def prepare
    IdentityCache.cache.clear
  end

  def run
    i = 0
    @count.times do
      ::Record.fetch(i)
      i+=1
    end
  end
end

class FetchHitRunner < CacheRunner

  def setup
    #@runner = FetchMissRunner.new(@count)
    #@runner.run
  end

  def run
    #@runner.run(@count)
  end
end

