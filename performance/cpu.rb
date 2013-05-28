require 'rubygems'
require 'benchmark'

require_relative 'cache_runner'

RUNS = 4000

class ARCreator
  include ActiveRecordObjects
end

def run(obj, bench)
  bench.report("#{obj.class.name}:") do
    obj.prepare
    obj.run
  end
end

create_database(RUNS)

Benchmark.bmbm do |x|
  run(FindRunner.new(RUNS), x)

  run(FetchMissRunner.new(RUNS), x)

  run(FetchHitRunner.new(RUNS), x)

end
