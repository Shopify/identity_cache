require File.dirname(__FILE__) + '/../test/test_helper'

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

class CacheRunner < IdentityCache::TestCase

  def initialize
  end

  def setup
    setup_models(FakeRecord)
  end

  def finish
    teardown
  end
end

class FindRunner < CacheRunner
  def run(run)
    i = 0
    run.times do
      ::Record.find(i)
      i+=1
    end
  end
end

class FetchMissRunner < CacheRunner
  def run(run)
    i = 0

    run.times do
      Record.fetch(i)
      i+=1
    end
  end
end

class FetchHitRunner < CacheRunner

  def run(run)
    raise "Run fetch_miss first to fill cache" unless @ran_fetch_miss
    fetch_miss(bench, run)
  end
end

