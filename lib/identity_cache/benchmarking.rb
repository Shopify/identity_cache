module IdentityCache
  module Benchmarking
    def self.included(base)
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def add_benchmark_to_method(method)
        method_name_without_benchmark = :"#{method}_on_#{self.name}_without_benchmark"

        raise ArgumentError, "already instrumented #{method} for #{self.name}" if method_defined? method_name_without_benchmark
        raise ArgumentError, "could not find method #{method} for #{self.name}" unless method_defined?(method) || private_method_defined?(method)

        alias_method method_name_without_benchmark, method

        define_method(method) do |*args, &block|

          if IdentityCache.logger.debug?
            result = nil

            time_ms = Benchmark.realtime do
              result = send(method_name_without_benchmark, *args, &block)
            end

            IdentityCache.logger.debug("[IdentityCache] call_time=#{(time_ms * 1000).round(2)} ms")

            result
          else
            send(method_name_without_benchmark, *args, &block)
          end
        end
      end
    end
  end
end
