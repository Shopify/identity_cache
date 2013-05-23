require 'rubygems'
require 'benchmark'
require 'ruby-prof'

require_relative 'cache_runner'

RUNS = 10000
RubyProf.measure_mode = RubyProf::CPU_TIME

def run(obj, bench)
  obj.prepare
  RubyProf.start
  obj.run
  result = RubyProf.stop
  puts "Results for #{obj.class.name}:"
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT)
end

a = FindRunner.new(RUNS)
a.setup
Benchmark.bmbm do |x|
  run(FindRunner.new(RUNS), x)

  run(FetchMissRunner.new(RUNS), x)

  run(FetchHitRunner.new(RUNS), x)
end
a.finish
