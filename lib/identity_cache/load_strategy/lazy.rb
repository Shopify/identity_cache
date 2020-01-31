# frozen_string_literal: true

module IdentityCache
  module LoadStrategy
    class Lazy
      def initialize
        @pending_loads = {}
      end

      def load(cache_fetcher, db_key)
        load_multi(cache_fetcher, [db_key]) do |results|
          yield results.fetch(db_key)
        end
        nil
      end

      def load_multi(cache_fetcher, db_keys, &callback)
        load_request = LoadRequest.new(db_keys, callback)

        if (prev_load_request = @pending_loads[cache_fetcher])
          if prev_load_request.instance_of?(MultiLoadRequest)
            prev_load_request.load_requests << load_request
          else
            @pending_loads[cache_fetcher] = MultiLoadRequest.new([prev_load_request, load_request])
          end
        else
          @pending_loads[cache_fetcher] = LoadRequest.new(db_keys, callback)
        end
        nil
      end

      def load_batch(db_keys_by_cache_fetcher)
        batch_result = {}
        db_keys_by_cache_fetcher.each do |cache_fetcher, db_keys|
          load_multi(cache_fetcher, db_keys) do |load_result|
            batch_result[cache_fetcher] = load_result
            if batch_result.size == db_keys_by_cache_fetcher.size
              yield batch_result
            end
          end
        end
        nil
      end

      def lazy_load
        yield self
        nil
      end

      def load_now
        until @pending_loads.empty?
          pending_loads = @pending_loads
          @pending_loads = {}
          load_pending(pending_loads)
        end
      end

      private

      def load_pending(pending_loads)
        result = CacheKeyLoader.load_batch(pending_loads.transform_values(&:db_keys))
        result.each do |cache_fetcher, load_result|
          load_request = pending_loads.fetch(cache_fetcher)
          load_request.after_load(load_result)
        end
      end
    end

    private_constant :Lazy
  end
end
