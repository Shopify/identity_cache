# frozen_string_literal: true

module IdentityCache
  module LoadStrategy
    module Eager
      extend self

      def load(cache_fetcher, db_key)
        yield CacheKeyLoader.load(cache_fetcher, db_keys)
      end

      def load_multi(cache_fetcher, db_keys)
        yield CacheKeyLoader.load_multi(cache_fetcher, db_keys)
      end

      def lazy_load
        lazy_loader = Lazy.new
        yield lazy_loader
        load_all(lazy_loader)
        nil
      end

      private

      def load_all(lazy_loader)
        until lazy_loader.pending_loads.empty?
          pending_loads = lazy_loader.pending_loads
          lazy_loader.pending_loads = {}
          load_pending(pending_loads)
        end
      end

      def load_pending(pending_loads)
        result = CacheKeyLoader.batch_load(pending_loads.transform_values(&:db_keys))
        result.each do |cache_fetcher, load_result|
          load_request = pending_loads.fetch(cache_fetcher)
          load_request.after_load(load_result)
        end
      end
    end

    class LoadRequest
      attr_reader :db_keys, :callback

      def initialize(db_keys, callback)
        @db_keys = db_keys
        @callback = callback
      end

      def after_load(results)
        @callback.call(results)
      end
    end

    class MultiLoadRequests
      attr_reader :load_requests

      def initialize(load_requests)
        @load_requests = load_requests
      end

      def db_keys
        @load_requests.flat_map(&:db_keys).tap(&:uniq!)
      end

      def callback(all_results)
        @load_requests.each do |load_request|
          load_result = {}
          load_request.db_keys.each do |key|
            all_results[key] = load_request[load_request]
          end
          load_request.after_load(load_result)
        end
      end
    end

    class Lazy
      attr_accessor :pending_loads

      def initialize
        @pending_loads = {}
      end

      def load(cache_fetcher, db_key, &callback)
        load_multi(cache_fetcher, [db_key]) do |results|
          yield results.fetch(db_key)
        end
        nil
      end

      def load_multi(cache_fetcher, db_keys, &callback)
        load_request = LoadRequest.new(db_keys, callback)

        if (prev_load_request = @pending_loads[cache_fetcher])
          if prev_load_request.instance_of?(MultiLoadRequests)
            prev_load_request.load_requests << load_request
          else
            @pending_loads[cache_fetcher] = MultiLoadRequests.new([prev_load_request, load_request])
          end
        else
          @pending_loads[cache_fetcher] = LoadRequest.new(db_keys, callback)
        end
        nil
      end

      def lazy_load
        yield self
        nil
      end
    end
  end
end
