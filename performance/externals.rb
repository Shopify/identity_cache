require 'rubygems'
require 'benchmark'
require File.expand_path '../externals_collector', __FILE__

require_relative 'cache_runner'

RUNS = 1000

def run(obj)
  puts "#{obj.class.name}:"
  obj.prepare
  count_events do
    obj.run
  end
end

def count_events(&block)
  mysql_events = ExternalsCollector.new(&block).events.select { |e| e.first == :mysql }.map { |e| e[1][:name] }
  memcached_events = ExternalsCollector.new(&block).events.select { |e| e.first == :memcached }.map { |e| e[1][:name] }
  puts "MySQL: #{mysql_events.count || 0}"
  puts "Memcached: #{memcached_events.count || 0}"
end

create_database(RUNS)

if runner_name = ENV['RUNNER']
  if runner = CACHE_RUNNERS.find{ |r| r.name == runner_name }
    run(runner.new(RUNS))
  else
    puts "Couldn't find cache runner #{runner_name.inspect}"
    exit 1
  end
else
  CACHE_RUNNERS.each do |runner|
    run(runner.new(RUNS))
  end
end

