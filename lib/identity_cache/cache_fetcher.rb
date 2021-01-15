# frozen_string_literal: true

require 'securerandom'

module IdentityCache
  class CacheFetcher
    attr_accessor :cache_backend

    EMPTY_HASH = {}.freeze

    class FillLock
      FILL_LOCKED = :fill_locked
      FAILED_CLIENT_ID = 'fill_failed'

      class << self
        def from_cache(marker, client_id, data_version)
          raise ArgumentError unless marker == FILL_LOCKED
          new(client_id: client_id, data_version: data_version)
        end

        def cache_value?(cache_value)
          cache_value.is_a?(Array) && cache_value.length == 3 && cache_value.first == FILL_LOCKED
        end
      end

      attr_reader :client_id, :data_version

      def initialize(client_id:, data_version:)
        @client_id = client_id
        @data_version = data_version
      end

      def cache_value
        [FILL_LOCKED, client_id, data_version]
      end

      def mark_failed
        @client_id = FAILED_CLIENT_ID
      end

      def fill_failed?
        @client_id == FAILED_CLIENT_ID
      end

      def ==(other)
        self.class == other.class && client_id == other.client_id && data_version == other.data_version
      end
    end

    def initialize(cache_backend)
      @cache_backend = cache_backend
    end

    def write(key, value)
      @cache_backend.write(key, value) if IdentityCache.should_fill_cache?
    end

    def delete(key)
      @cache_backend.write(key, IdentityCache::DELETED, expires_in: IdentityCache::DELETED_TTL.seconds)
    end

    def clear
      @cache_backend.clear
    end

    def fetch_multi(keys, &block)
      results = cas_multi(keys, &block)
      results = add_multi(keys, &block) if results.nil?
      results
    end

    def fetch(key, fill_lock_duration: nil, lock_wait_tries: 2)
      if fill_lock_duration && IdentityCache.should_fill_cache?
        fetch_with_fill_lock(key, fill_lock_duration, lock_wait_tries) do
          yield
        end
      else
        fetch_without_fill_lock(key) { yield }
      end
    end

    private

    def fetch_without_fill_lock(key)
      data = nil
      upsert(key) do |value|
        value = nil if value == IdentityCache::DELETED || FillLock.cache_value?(value)
        unless value.nil?
          return value
        end
        data = yield
        break unless IdentityCache.should_fill_cache?
        data
      end
      data
    end

    def fetch_with_fill_lock(key, fill_lock_duration, lock_wait_tries)
      raise ArgumentError, 'fill_lock_duration must be greater than 0.0' unless fill_lock_duration > 0.0
      raise ArgumentError, 'lock_wait_tries must be greater than 0' unless lock_wait_tries > 0
      lock = nil
      using_fallback_key = false
      expiration_options = EMPTY_HASH
      (lock_wait_tries + 2).times do # +2 is for first attempt and retry with fallback key
        result = fetch_or_take_lock(key, old_lock: lock, **expiration_options)
        case result
        when FillLock
          lock = result
          if lock.client_id == client_id # have lock
            data = begin
              yield
            rescue
              mark_fill_failure_on_lock(key, expiration_options)
              raise
            end

            if !fill_with_lock(key, data, lock, expiration_options) && !using_fallback_key
              # fallback to storing data in the fallback key so it is available to clients waiting on the lock
              expiration_options = fallback_key_expiration_options(fill_lock_duration)
              @cache_backend.write(lock_fill_fallback_key(key, lock), data, expiration_options)
            end
            return data
          else
            raise LockWaitTimeout if lock_wait_tries <= 0
            lock_wait_tries -= 1

            # If fill failed in the other client, then it might be failing fast
            # so avoid waiting the typical amount of time for a lock wait. The
            # semian gem can be used to handle failing fast when the database is slow.
            if lock.fill_failed?
              return fetch_without_fill_lock(key) { yield }
            end

            # lock wait
            sleep(fill_lock_duration)
            # loop around to retry fetch_or_take_lock
          end
        when IdentityCache::DELETED # interrupted by cache invalidation
          if using_fallback_key
            raise "unexpected cache invalidation of versioned fallback key"
          elsif lock
            # Cache invalidated during lock wait, use a versioned fallback key
            # to avoid further cache invalidation interruptions.
            using_fallback_key = true
            key = lock_fill_fallback_key(key, lock)
            expiration_options = fallback_key_expiration_options(fill_lock_duration)
            # loop around to retry with fallback key
          else
            # Cache invalidation prevented lock from being taken or read, so we don't
            # have a data version to use to build a shared fallback key. In the future
            # we could add the data version to the cache invalidation value so a fallback
            # key could be used here. For now, we assume that a cache invalidation occuring
            # just after the cache wasn't filled is more likely a sign of a key that is
            # written more than read (which this cache isn't a good fit for), rather than
            # a thundering herd or reads.
            return yield
          end
        when nil # Errors talking to memcached
          return yield
        else # hit
          return result
        end
      end
      raise "unexpected number of loop iterations"
    end

    def mark_fill_failure_on_lock(key, expiration_options)
      @cache_backend.cas(key, expiration_options) do |value|
        break unless FillLock.cache_value?(value)
        lock = FillLock.from_cache(*value)
        break if lock.client_id != client_id
        lock.mark_failed
        lock.cache_value
      end
    end

    def upsert(key, expiration_options = EMPTY_HASH)
      yielded = false
      upserted = @cache_backend.cas(key, expiration_options) do |value|
        yielded = true
        yield value
      end
      unless yielded
        data = yield nil
        upserted = add(key, data, expiration_options)
      end
      upserted
    end

    def fetch_or_take_lock(key, old_lock:, **expiration_options)
      new_lock = nil
      upserted = upsert(key, expiration_options) do |value|
        if value.nil? || value == IdentityCache::DELETED
          if old_lock # cache invalidated
            return value
          else
            new_lock = FillLock.new(client_id: client_id, data_version: SecureRandom.uuid)
          end
        elsif FillLock.cache_value?(value)
          fetched_lock = FillLock.from_cache(*value)
          if old_lock == fetched_lock
            # preserve data version since there hasn't been any cache invalidations
            new_lock = FillLock.new(client_id: client_id, data_version: old_lock.data_version)
          elsif old_lock && fetched_lock.data_version != old_lock.data_version
            # Cache was invalidated, then another lock was taken during a lock wait.
            # Treat it as any other cache invalidation, where the caller will switch
            # to the fallback key.
            return IdentityCache::DELETED
          else
            return fetched_lock
          end
        else # hit
          return value
        end
        new_lock.cache_value # take lock
      end

      return new_lock if upserted

      value = @cache_backend.read(key)
      if FillLock.cache_value?(value)
        FillLock.from_cache(*value)
      else
        value
      end
    end

    def fill_with_lock(key, data, my_lock, expiration_options)
      upserted = upsert(key, expiration_options) do |value|
        return false if value.nil? || value == IdentityCache::DELETED
        return true unless FillLock.cache_value?(value) # already filled
        current_lock = FillLock.from_cache(*value)
        if current_lock.data_version != my_lock.data_version
          return false # invalidated then relocked
        end
        data
      end

      upserted
    end

    def lock_fill_fallback_key(key, lock)
      "lock_fill:#{lock.data_version}:#{key}"
    end

    def fallback_key_expiration_options(fill_lock_duration)
      # Override the default TTL for the fallback key lock since it won't be used for very long.
      expires_in = fill_lock_duration * 2

      # memcached uses integer number of seconds for TTL so round up to avoid having
      # the cache store round down with `to_i`
      expires_in = expires_in.ceil

      # memcached TTL only gets part of the first second (https://github.com/memcached/memcached/issues/307),
      # so increase TTL by 1 to compensate
      expires_in += 1

      { expires_in: expires_in }
    end

    def client_id
      @client_id ||= SecureRandom.uuid
    end

    def cas_multi(keys)
      result = nil
      @cache_backend.cas_multi(*keys) do |results|
        deleted = results.select { |_, v| IdentityCache::DELETED == v }
        results.reject! { |_, v| IdentityCache::DELETED == v }

        result = results
        updates = {}
        missed_keys = keys - results.keys
        unless missed_keys.empty?
          missed_vals = yield missed_keys
          missed_keys.zip(missed_vals) do |k, v|
            result[k] = v
            if deleted.include?(k)
              updates[k] = v
            else
              add(k, v)
            end
          end
        end

        break if updates.empty?
        break unless IdentityCache.should_fill_cache?
        updates
      end
      result
    end

    def add_multi(keys)
      values = yield keys
      result = Hash[keys.zip(values)]
      result.each { |k, v| add(k, v) }
    end

    def add(key, value, expiration_options = EMPTY_HASH)
      return false unless IdentityCache.should_fill_cache?
      @cache_backend.write(key, value, { unless_exist: true, **expiration_options })
    end
  end
end
