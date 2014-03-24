$LOAD_PATH.unshift File.expand_path("../../../lib", __FILE__)

require 'active_record'
require 'memcached_store'
require_relative 'serialization_format'
require_relative 'cache'
require_relative 'database_connection'
require_relative 'active_record_objects'
require 'identity_cache'

if ENV['BOXEN_HOME'].present?
  $memcached_port = 21211
  $mysql_port = 13306
else
  $memcached_port = 11211
  $mysql_port = 3306
end

include SerializationFormat
include ActiveRecordObjects

DatabaseConnection.setup
DatabaseConnection.drop_tables
DatabaseConnection.create_tables
setup_models
File.open(serialized_record_file, 'w') {|file| serialize(serialized_record, file) }
puts "Serialized record to #{serialized_record_file}"
IdentityCache.cache.clear
teardown_models
