require 'rubygems'
require 'benchmark'
require_relative 'cache_runner'

RUNS = 10000

def run(obj, bench, runs)
  bench.report("#{obj.class.name}:") do
    obj.setup
    obj.run(runs)
    obj.finish
  end
end

Benchmark.bmbm do |x|
  run(FindRunner.new, x, RUNS)

  run(FetchMissRunner.new, x, RUNS)

#  runner.fetch_hit(x, RUNS)

#  runner.fetch_multi(x, RUNS)
end
