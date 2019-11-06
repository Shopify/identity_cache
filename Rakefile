#!/usr/bin/env rake
require 'bundler/gem_tasks'

require 'rake/testtask'
require 'rdoc/task'

desc('Default: run unit tests.')
task(:default => :test)

desc('Test the identity_cache plugin.')
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc('Update serialization format test fixture.')
task :update_serialization_format do
  %w(mysql2 postgresql).each do |db|
    ENV["DB"] = db
    ruby './test/helpers/update_serialization_format.rb'
  end
end

namespace :benchmark do
  desc "Run the identity cache CPU benchmark"
  task :cpu do
    ruby "./performance/cpu.rb"
  end

  task :externals do
    ruby "./performance/externals.rb"
  end
end

namespace :profile do
  desc "Profile IDC code"
  task :run do
    ruby "./performance/profile.rb"
  end
end
