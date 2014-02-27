require 'rubygems'
require 'benchmark'
require 'stackprof'

require_relative 'cache_runner'

RUNS = 1000

def run(obj)
  puts "#{obj.class.name}:"
  obj.prepare
  data = StackProf.run(mode: :cpu) do
    obj.run
  end
  StackProf::Report.new(data).print_text(false, 20)
  puts
end

create_database(RUNS)

run(FindRunner.new(RUNS))

run(FetchMissRunner.new(RUNS))

run(FetchHitRunner.new(RUNS))

run(DoubleFetchHitRunner.new(RUNS))

run(DoubleFetchMissRunner.new(RUNS))
