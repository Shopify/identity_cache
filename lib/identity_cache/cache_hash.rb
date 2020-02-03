# frozen_string_literal: true
# Use CityHash for fast hashing if it is available; use Digest::MD5 otherwise
begin
  require 'cityhash'
rescue LoadError
  unless RUBY_PLATFORM == 'java'
    warn(<<-NOTICE)
      ** Notice: CityHash was not loaded. **

      For optimal performance, use of the cityhash gem is recommended.

      Run the following command, or add it to your Gemfile:

        gem install cityhash
    NOTICE
  end

  require 'digest/md5'
end

module IdentityCache
  module CacheHash
    if defined?(CityHash)

      def memcache_hash(key) #:nodoc:
        CityHash.hash64(key)
      end
    else

      def memcache_hash(key) #:nodoc:
        a = Digest::MD5.digest(key).unpack('LL')
        (a[0] << 32) | a[1]
      end
    end
  end
end
