require "test_helper"

class BenchmarkingTest < IdentityCache::TestCase

  class BenchmarkingSample
    include IdentityCache::Benchmarking

    def test_a(param, &block)
      test_b(param, &block)
    end

    def test_b(param, &block)
      # noop
    end

    add_benchmark_to_method :test_a
  end

  def setup
    super

    IdentityCache.logger = Logger.new(nil)
    IdentityCache.logger.level = 0

    @instance = BenchmarkingSample.new
  end

  def test_add_benchmark_report_execution_time_in_logs
    IdentityCache.logger.expects(:debug).with do |text|
      text[/\[IdentityCache\] call_time=\d+\.\d{1,2} ms/]
    end

    @instance.test_a(nil)
  end

  def test_add_benchmark_forward_method_call
    block = begin
      # noop
    end

    @instance.expects(:test_b).with(1, &block)

    @instance.test_a(1, &block)
  end

  def test_add_benchmark_skip_when_log_level_is_greater_than_debug
    IdentityCache.logger.level = 1

    block = begin
      # noop
    end

    IdentityCache.logger.expects(:debug).never
    Benchmark.expects(:realtime).never

    @instance.expects(:test_b).with(1, &block)

    @instance.test_a(1, &block)
  end

  def test_add_benchmark_raises_when_benchmarking_a_non_existing_method
    e = assert_raises ArgumentError do
      BenchmarkingSample.send(:add_benchmark_to_method, :unknown)
    end
    assert_equal 'could not find method unknown for BenchmarkingTest::BenchmarkingSample', e.message
  end

  def test_add_benchmark_raises_when_benchmarking_the_same_method_twice
    e = assert_raises ArgumentError do
      BenchmarkingSample.send(:add_benchmark_to_method, :test_a)
    end
    assert_equal 'already instrumented test_a for BenchmarkingTest::BenchmarkingSample', e.message
  end
end
