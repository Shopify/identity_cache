# frozen_string_literal: true
module IdentityCache
  module RedisCAS
    ##
    # Get the value and CAS ID associated with the key.  If a block is provided,
    # value and CAS will be passed to the block.
    def get_cas(key)
      (value, cas) = synchronize { |client| client.call(["cas.get", key]) }
      if block_given?
        yield value, cas
      else
        [value, cas]
      end
    end

    ##
    # Fetch multiple keys efficiently, including available metadata such as CAS.
    # If a block is given, yields key/data pairs one a time.  Data is an array:
    # [value, cas_id]
    # If no block is given, returns a hash of
    #   { 'key' => [value, cas_id] }
    def get_multi_cas(*keys)
      vals = synchronize { |client| client.call(["cas.mget", keys]) }
      if block_given?
        vals.map { |value, cas| yield [value, cas] }
      else
        {}.tap do |hash|
          keys.zip(vals).each { |k, vc| hash[k] = vc }
        end
      end
    end

    ##
    # Set the key-value pair, verifying existing CAS.
    # Returns the resulting CAS value if succeeded, and falsy otherwise.
    def set_cas(key, value, cas, ttl = nil, _options = nil)
      ttl ||= @options[:expires_in].to_i
      synchronize { |client| client.call(["cas.set", key, value, cas, "ex", ttl]) }
    end

    ##
    # Set the key-value pair, verifying existing CAS.
    # Returns the resulting CAS value if succeeded, and falsy otherwise.
    def set_multi_cas(pairs, ttl = nil, options = nil)
      cmd = pairs[0]
      cmd.concat(options) if options
      ttl ||= @options[:expires_in].to_i
      cmd.concat(["ex", ttl]) if ttl
      cmd += pairs[1..-1]
      cmd.unshift("cas.mset")
      puts cmd
      synchronize { |client| client.call(cmd) }
    end

    ##
    # Conditionally add a key/value pair, verifying existing CAS, only if the
    # key already exists on the server.  Returns the new CAS value if the
    # operation succeeded, or falsy otherwise.
    def replace_cas(key, value, cas, ttl = nil, _options = nil)
      ttl ||= @options[:expires_in].to_i
      synchronize { |client| client.call(["cas.set", key, value, cas, "xx", "ex", ttl]) }
    end

    # Delete a key/value pair, verifying existing CAS.
    # Returns true if succeeded, and falsy otherwise.
    # TODO; tanner
    def delete_cas(key, _cas = 0)
      synchronize { |client| client.call(["unlink", key]) }
    end

    def cas(key, ttl = nil, _options = nil)
      ttl ||= @options[:expires_in].to_i
      (value, cas) = synchronize { |client| client.call(["cas.get", key]) }

      return if value.nil?
      newvalue = yield(value)

      synchronize { |client| client.call(["cas.set", key, newvalue, cas, "ex", ttl_or_default(ttl)]) }
    end
  end
end
