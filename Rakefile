#!/usr/bin/env rake
# frozen_string_literal: true

require "bundler/gem_tasks"

require "rake/testtask"
require "rdoc/task"

desc("Default: run tests and style checks.")
task(default: [:test, :rubocop])

namespace :test do
  desc "Test the identity_cache plugin with default Gemfile"
  Rake::TestTask.new(:default) do |t|
    t.libs << "lib"
    t.libs << "test"
    t.pattern = "test/**/*_test.rb"
    t.verbose = true
  end

  desc "Test the identity_cache plugin with minimum supported dependencies"
  task :min_supported do
    gemfile = File.expand_path("gemfiles/Gemfile.min-supported", __dir__)

    puts "Installing dependencies for #{gemfile}..."
    Bundler.with_unbundled_env do
      system("bundle install --gemfile #{gemfile}") || abort("Bundle install failed")
    end

    puts "Running tests with #{gemfile}..."
    Rake::TestTask.new(:run_min_supported) do |t|
      t.libs << "lib"
      t.libs << "test"
      t.pattern = "test/**/*_test.rb"
      t.verbose = true
    end
    Rake::Task["run_min_supported"].invoke
  end

  desc "Test the identity_cache plugin with latest released dependencies"
  task :latest_release do
    gemfile = File.expand_path("gemfiles/Gemfile.latest-release", __dir__)

    puts "Installing dependencies for #{gemfile}..."
    Bundler.with_unbundled_env do
      system("bundle install --gemfile #{gemfile}") || abort("Bundle install failed")
    end

    puts "Running tests with #{gemfile}..."
    Rake::TestTask.new(:run_latest_release) do |t|
      t.libs << "lib"
      t.libs << "test"
      t.pattern = "test/**/*_test.rb"
      t.verbose = true
    end
    Rake::Task["run_latest_release"].invoke
  end

  desc "Test the identity_cache plugin with rails edge dependencies"
  task :rails_edge do
    gemfile = File.expand_path("gemfiles/Gemfile.rails-edge", __dir__)

    puts "\nInstalling dependencies for #{gemfile}..."
    Bundler.with_unbundled_env do
      system("bundle install --gemfile #{gemfile}") || abort("Bundle install failed")
    end

    puts "Running tests with #{gemfile}..."
    Rake::TestTask.new(:run_rails_edge) do |t|
      t.libs << "lib"
      t.libs << "test"
      t.pattern = "test/**/*_test.rb"
      t.verbose = true
    end
    Rake::Task["run_rails_edge"].invoke
  end
end

desc "Run default tests"
task test: ["test:default"]

desc "Run all tests (default, min_supported, latest_release, rails_edge)"
task test_all: ["test:default", "test:min_supported", "test:latest_release", "test:rails_edge"]

task :rubocop do
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
end

desc("Update serialization format test fixture.")
task :update_serialization_format do
  ["mysql2", "postgresql"].each do |db|
    ENV["DB"] = db
    ruby "./test/helpers/update_serialization_format.rb"
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

namespace :db do
  desc "Create the identity_cache_test database"
  task :create do
    require "mysql2"

    config = {
      host: ENV.fetch("MYSQL_HOST") || "localhost",
      port: ENV.fetch("MYSQL_PORT") || 1037,
      username: ENV.fetch("MYSQL_USER") || "root",
      password: ENV.fetch("MYSQL_PASSWORD") || "",
    }

    begin
      client = Mysql2::Client.new(config)
      client.query("CREATE DATABASE IF NOT EXISTS identity_cache_test")
      puts "Database 'identity_cache_test' created successfully. host: #{config[:host]}, port: #{config[:port]}"
    rescue Mysql2::Error => e
      puts "Error creating database: #{e.message}"
    ensure
      client&.close
    end
  end
end
