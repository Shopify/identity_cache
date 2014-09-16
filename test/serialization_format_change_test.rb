require "test_helper"
require "helpers/serialization_format"

class SerializationFormatChangeTest < IdentityCache::TestCase
  include SerializationFormat

  MESSAGE = "serialization format changed => increment IdentityCache.CACHE_VERSION and run rake update_serialization_format"

  def test_serialization_format_has_not_changed
    serialization = Marshal.load(serialize(serialized_record))
    preserialization = Marshal.load(File.binread(serialized_record_file))
    assert_equal(preserialization, serialization, MESSAGE)
  rescue SystemCallError
    assert(false, MESSAGE)
  end
end

class SerializationFormatChangeSnappyPackTest < SerializationFormatChangeTest
  include IdentityCache::SnappyPackTestCase
end

