# Use a hashing library for fast hashing if it is available; use Digest::MD5 otherwise
AVAILABLE_HASHING_GEMS = %w{xxhash murmurhash3 cityhash}

hash_loaded = false
AVAILABLE_HASHING_GEMS.each do |gem|
  begin
    require gem
    hash_loaded = true
    break
  rescue LoadError
    # Hashing library not loaded
  end
end

unless hash_loaded
  unless RUBY_PLATFORM == 'java'
    warn <<-NOTICE
      ** Notice: no hashing library loaded. **

      For optimal performance, use of one of #{AVAILABLE_HASHING_GEMS.join('|')} gem is recommended.
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

    elsif defined?(XXhash)

      def memcache_hash(key) #:nodoc:
        XXhash.xxh64(key)
      end

    elsif defined?(MurmurHash3)

      def memcache_hash(key) #:nodoc:
        a = MurmurHash3::V128.str_hash(key)
        (a[0] << 32) | a[1]
      end

    else

      def memcache_hash(key) #:nodoc:
        a = Digest::MD5.digest(key).unpack('LL')
        (a[0] << 32) | a[1]
      end

    end

  end
end
