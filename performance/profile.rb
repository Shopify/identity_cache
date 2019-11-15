# frozen_string_literal: true
require 'rubygems'
require 'benchmark'
require 'stackprof'

require_relative 'cache_runner'

RUNS = 1000

def run(obj, filename: nil)
  puts "#{obj.class.name}:"
  obj.prepare
  data = StackProf.run(mode: :cpu) do
    obj.run
  end
  StackProf::Report.new(data).print_text(false, 20)
  File.write(filename, Marshal.dump(data)) if filename
  puts
ensure
  obj.cleanup
end

create_database(RUNS)

if (runner_name = ENV['RUNNER'])
  if (runner = CACHE_RUNNERS.find { |r| r.name == runner_name })
    run(runner.new(RUNS), filename: ENV['FILENAME'])
  else
    puts "Couldn't find cache runner #{runner_name.inspect}"
    exit(1)
  end
else
  CACHE_RUNNERS.each do |runner|
    run(runner.new(RUNS))
  end
end
