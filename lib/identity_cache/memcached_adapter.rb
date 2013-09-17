module IdentityCache
  class MemcachedAdapter < ::Memcached

    FATAL_EXCEPTIONS = [ Memcached::ABadKeyWasProvidedOrCharactersOutOfRange,
      Memcached::AKeyLengthOfZeroWasProvided,
      Memcached::ConnectionBindFailure,
      Memcached::ConnectionDataDoesNotExist,
      Memcached::ConnectionFailure,
      Memcached::ConnectionSocketCreateFailure,
      Memcached::CouldNotOpenUnixSocket,
      Memcached::NoServersDefined,
      Memcached::TheHostTransportProtocolDoesNotMatchThatOfTheClient
    ]
    NONFATAL_EXCEPTIONS = Memcached::EXCEPTIONS - FATAL_EXCEPTIONS

    def initialize(servers = nil, opts = {})
      super(servers, opts.merge(support_cas: true))
    end

    %w{delete incr decr append prepend}.each do |meth|
      define_method(meth) do |*args|
        begin
          super(*args)
        rescue *NONFATAL_EXCEPTIONS
        end
      end
    end

    def get(key)
      value = super(key)
      cas = @struct.result.cas
      [value, cas]
    rescue *NONFATAL_EXCEPTIONS
    end

    def add(key, value)
      super(key, value, 0)
    rescue *NONFATAL_EXCEPTIONS
      false
    end

    def cas(key, value, cas, encode=true, flags=FLAGS)
      value, flags = @codec.encode(key, value, flags) if encode
      ttl = 0

      begin
        check_return_code(
          Lib.memcached_cas(@struct, key, value, ttl, flags, cas),
          key
          )
      rescue => e
        tries_for_cas ||= 0
        raise unless tries_for_cas < options[:exception_retry_limit] && should_retry(e)
        tries_for_cas += 1
        retry
      end

    rescue *NONFATAL_EXCEPTIONS
      false
    end

    def replace(key, value, ttl = 0)
      super(key, value, ttl)
    rescue *NONFATAL_EXCEPTIONS
      false
    end

  end
end
