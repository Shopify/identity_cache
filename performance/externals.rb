# frozen_string_literal: true
require 'rubygems'
require 'benchmark'
require 'ruby-prof'

require_relative 'cache_runner'

RUNS = 1000
RubyProf.measure_mode = RubyProf::CPU_TIME

EXTERNALS = {"Memcache" => ["MemCache#set", "MemCache#get"],
             "Database" => ["Mysql2::Client#query"]}

def run(obj)
  obj.prepare
  RubyProf.start
  obj.run
  result = RubyProf.stop
  puts "Results for #{obj.class.name}:"
  results = StringIO.new
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(results)
  count_externals(results.string)
end

def count_externals(results)
  count = {}
  results.split(/\n/).each do |line|
    fields = line.split
    if ext = EXTERNALS.detect { |e| e[1].any? { |method| method == fields[-1] } }
      count[ext[0]] ||= 0
      count[ext[0]] += fields[-2].to_i
    end
  end
  EXTERNALS.each do |ext|
    puts "#{ext[0]}: #{count[ext[0]] || 0}"
  end
end

create_database(RUNS)

run(FindRunner.new(RUNS))

run(FetchHitRunner.new(RUNS))

run(FetchMissRunner.new(RUNS))

run(DoubleFetchHitRunner.new(RUNS))

run(DoubleFetchMissRunner.new(RUNS))
