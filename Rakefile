#!/usr/bin/env rake
# frozen_string_literal: true

require "bundler/gem_tasks"

require "rake/testtask"
require "rdoc/task"

desc("Default: run tests and style checks.")
task(default: [:test, :rubocop])

desc("Test the identity_cache plugin.")
Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

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
