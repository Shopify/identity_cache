require "test_helper"
require "helpers/serialization_format"

class SerializationFormatChangeTest < IdentityCache::TestCase
  include SerializationFormat

  MESSAGE = "serialization format changed => increment IdentityCache.CACHE_VERSION and run rake update_serialization_format"

  def test_serialization_format_has_not_changed
    serialization = serialize(serialized_record)
    preserialization = File.binread(serialized_record_file)
    assert_equal(preserialization, serialization, MESSAGE)
  end
end
