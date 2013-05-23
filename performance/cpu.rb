require 'rubygems'
require 'benchmark'

require_relative 'cache_runner'

RUNS = 10000

class ARCreator
  include ActiveRecordObjects
end

def run(obj, bench)
  obj.prepare
  bench.report("#{obj.class.name}:") do
    obj.run
  end
end

a = FindRunner.new(RUNS)
a.setup
Benchmark.bmbm do |x|
  run(FindRunner.new(RUNS), x)

  run(FetchMissRunner.new(RUNS), x)

  run(FetchHitRunner.new(RUNS), x)
end
a.finish
