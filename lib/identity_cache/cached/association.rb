# frozen_string_literal: true
module IdentityCache
  module Cached
    class Association # :nodoc:
      include EmbeddedFetching

      def initialize(name, inverse_name:, reflection:)
        @name = name
        @reflection = reflection
        @inverse_name = inverse_name
        @cached_accessor_name = :"fetch_#{name}"
        @records_variable_name = :"@cached_#{name}"
      end

      attr_reader :name, :reflection, :cached_accessor_name, :records_variable_name

      def build
        raise NotImplementedError
      end

      def read(_record)
        raise NotImplementedError
      end

      def write(_record, _value)
        raise NotImplementedError
      end

      def clear(_record)
        raise NotImplementedError
      end

      def fetch(_records)
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

      def validate
        parent_class = reflection.active_record
        child_class  = reflection.klass

        unless child_class < IdentityCache
          if embedded_recursively?
            raise UnsupportedAssociationError, <<~MSG.squish
              cached association #{parent_class}\##{reflection.name} requires
              associated class #{child_class} to include IdentityCache
              or IdentityCache::WithoutPrimaryIndex
            MSG
          else
            raise UnsupportedAssociationError, <<~MSG.squish
              cached association #{parent_class}\##{reflection.name} requires
              associated class #{child_class} to include IdentityCache
            MSG
          end
        end

        unless child_class.reflect_on_association(inverse_name)
          raise InverseAssociationError, <<~MSG.squish
            Inverse name for association #{parent_class}\##{reflection.name} could
            not be determined. Please use the :inverse_name option to specify
            the inverse association name for this cache.
          MSG
        end
      end
    end
  end
end
