# frozen_string_literal: true

module IdentityCache
  module Internal
    module Reference
      class Association < Internal::Association
        def embedded_by_reference?
          true
        end

        def embedded_recursively?
          false
        end
      end
    end
  end
end
