# frozen_string_literal: true

module IdentityCache
  module LoadStrategy
    class LoadRequest
      attr_reader :db_keys

      def initialize(db_keys, callback)
        @db_keys = db_keys
        @callback = callback
      end

      def after_load(results)
        @callback.call(results)
      end
    end

    private_constant :LoadRequest
  end
end
