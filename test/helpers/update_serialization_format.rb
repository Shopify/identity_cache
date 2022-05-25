# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../../lib", __FILE__))

require "logger"
require "active_record"
require "memcached_store"
require "active_support/cache/memcached_store"
require_relative "serialization_format"
require_relative "database_connection"
require_relative "cache_connection"
require_relative "active_record_objects"
require "identity_cache"

include(SerializationFormat)
include(ActiveRecordObjects)

DatabaseConnection.setup
DatabaseConnection.drop_tables
DatabaseConnection.create_tables
IdentityCache.logger = Logger.new(nil)
CacheConnection.setup
setup_models
File.open(serialized_record_file, "w") { |file| serialize(serialized_record, file) }
puts "Serialized record to #{serialized_record_file}"
IdentityCache.cache.clear
teardown_models
