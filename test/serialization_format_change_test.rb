# frozen_string_literal: true
require "test_helper"
require "helpers/serialization_format"

class SerializationFormatChangeTest < IdentityCache::TestCase
  include SerializationFormat

  MESSAGE = <<~MSG.squish
    serialization format changed => increment
    IdentityCache.CACHE_VERSION and run rake update_serialization_format
  MSG

  def test_serialization_format_has_not_changed
    serialization = Marshal.load(serialize(serialized_record))
    preserialization = Marshal.load(File.binread(serialized_record_file))
    assert_equal(preserialization, serialization, MESSAGE)
  rescue SystemCallError
    assert(false, MESSAGE)
  end
end
