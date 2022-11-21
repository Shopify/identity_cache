# frozen_string_literal: true

# Allows to easily simulate a single broken call to backend
# with a passthrough for everything else.
class MockedCacheBackend < SimpleDelegator
  def write(key, value, options = {})
    if stubbed_calls[0] == [key, value]
      stubbed_calls.shift
      return false
    end

    super
  end

  def stub_call(key, value)
    stubbed_calls << [key, value]
  end

  def stubbed_calls
    @stubbed_calls ||= []
  end
end
