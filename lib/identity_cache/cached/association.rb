module IdentityCache
  module Cached
    class Association # :nodoc:
      def initialize(name, inverse_name:, reflection:)
        @name = name
        @reflection = reflection
        @inverse_name = inverse_name
        @cached_accessor_name = "fetch_#{name}"
        @records_variable_name = :"@cached_#{name}"
      end

      attr_reader :name, :reflection, :cached_accessor_name, :records_variable_name

      def build
        raise NotImplementedError
      end

      def clear(record)
        raise NotImplementedError
      end

      def embedded?
        embedded_by_reference? || embedded_recursively?
      end

      def embedded_by_reference?
        raise NotImplementedError
      end

      def embedded_recursively?
        raise NotImplementedError
      end

      def inverse_name
        @inverse_name ||= begin
          reflection.inverse_of&.name ||
          reflection.active_record.name.underscore
        end
      end
    end
  end
end
