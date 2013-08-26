require "test_helper"
require "helpers/serialization_format"

class UpdateSerializationFormat < IdentityCache::TestCase
  include SerializationFormat

  def test_reserialize_record
    File.open(serialized_record_file, 'w') {|file| serialize(serialized_record, file) }
  end
end
