module IdentityCache
  module Cached
    module Reference
      class Association < Cached::Association # :nodoc:
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
