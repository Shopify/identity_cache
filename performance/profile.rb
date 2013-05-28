require 'rubygems'
require 'benchmark'
require 'ruby-prof'

require_relative 'cache_runner'

RUNS = 1000
RubyProf.measure_mode = RubyProf::CPU_TIME

def run(obj)
  obj.prepare
  RubyProf.start
  obj.run
  result = RubyProf.stop
  puts "Results for #{obj.class.name}:"
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT)
end

create_database(RUNS)

run(FindRunner.new(RUNS))

run(FetchMissRunner.new(RUNS))

run(FetchHitRunner.new(RUNS))
