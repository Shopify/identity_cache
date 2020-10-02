# frozen_string_literal: true
require 'rubygems'
require 'benchmark'

require_relative 'cache_runner'

RUNS = 400

class ARCreator
  include ActiveRecordObjects
end

def run(obj)
  obj.prepare
  GC.start
  Benchmark.measure do
    obj.run
  end
ensure
  obj.cleanup
end

def benchmark(runners, label_width = 0)
  IdentityCache.cache.clear
  runners.each do |runner|
    print("#{runner.name}: ".ljust(label_width))
    puts run(runner.new(RUNS))
  end
end

def bmbm(runners)
  label_width = runners.map { |r| r.name.size }.max + 2
  width = label_width + Benchmark::CAPTION.size

  puts 'Rehearsal: '.ljust(width, '-')
  benchmark(runners, label_width)
  puts '-' * width

  benchmark(runners, label_width)
end

create_database(RUNS)

bmbm(CACHE_RUNNERS)
