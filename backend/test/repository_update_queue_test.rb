# frozen_string_literal: true

require "stringio"
require "timeout"

require_relative "test_helper"

module UpdateViewer
  class RepositoryUpdateQueueTest < Minitest::Test
    def setup
      @logger_io = StringIO.new
      @logger = Logger.new(@logger_io)
    end

    def test_enqueue_processes_job_successfully
      recorded_paths = ::Queue.new
      catalog = Object.new
      catalog.define_singleton_method(:register_summary_from_path) do |path|
        recorded_paths << path
      end

      generator_result = SummaryGenerator::Result.new(
        stdout: "ok",
        stderr: "",
        thread_id: "thread-1",
        output_path: "/tmp/generated.md"
      )

      generator_factory = lambda do |_organization, _repository|
        Object.new.tap do |generator|
          generator.define_singleton_method(:call) { generator_result }
        end
      end

      queue = RepositoryUpdateQueue.new(
        catalog: catalog,
        logger: @logger,
        generator_factory: generator_factory
      )

      enqueued = queue.enqueue(organization: "octocat", repository: "hello-world")

      assert enqueued
      assert_equal "/tmp/generated.md", wait_for_queue_value(recorded_paths)
      wait_until_idle(queue)
    ensure
      queue&.shutdown
    end

    def test_enqueue_logs_execution_error_when_generator_fails
      register_calls = ::Queue.new
      catalog = Object.new
      catalog.define_singleton_method(:register_summary_from_path) do |_path|
        register_calls << :called
      end

      execution_error = SummaryGenerator::ExecutionError.new(
        "boom",
        stdout: "out",
        stderr: "err",
        status: 1
      )

      generator_factory = lambda do |_organization, _repository|
        Object.new.tap do |generator|
          generator.define_singleton_method(:call) { raise execution_error }
        end
      end

      queue = RepositoryUpdateQueue.new(
        catalog: catalog,
        logger: @logger,
        generator_factory: generator_factory
      )

      enqueued = queue.enqueue(organization: "octocat", repository: "broken")

      assert enqueued
      wait_until_idle(queue)
      assert register_calls.empty?, "register_summary_from_path should not be called"
      assert_includes @logger_io.string, "[queue] Summary generation failed for octocat/broken"
    ensure
      queue&.shutdown
    end

    def test_enqueue_logs_registration_error_when_catalog_update_fails
      registration_error = StandardError.new("failed")

      catalog = Object.new
      catalog.define_singleton_method(:register_summary_from_path) do |_path|
        raise registration_error
      end

      generator_result = SummaryGenerator::Result.new(
        stdout: "",
        stderr: "",
        thread_id: nil,
        output_path: "/tmp/output.md"
      )

      generator_factory = lambda do |_organization, _repository|
        Object.new.tap do |generator|
          generator.define_singleton_method(:call) { generator_result }
        end
      end

      queue = RepositoryUpdateQueue.new(
        catalog: catalog,
        logger: @logger,
        generator_factory: generator_factory
      )

      enqueued = queue.enqueue(organization: "octocat", repository: "failing")

      assert enqueued
      wait_until_idle(queue)
      assert_includes(
        @logger_io.string,
        "[queue] Failed to register summary for octocat/failing path=/tmp/output.md error=#{registration_error.class}: #{registration_error.message}"
      )
    ensure
      queue&.shutdown
    end

    def test_jobs_are_processed_in_fifo_order
      order = []

      catalog = Object.new
      catalog.define_singleton_method(:register_summary_from_path) { |_path| }

      generator_factory = lambda do |organization, repository|
        Object.new.tap do |generator|
          generator.define_singleton_method(:call) do
            order << "#{organization}/#{repository}"
            SummaryGenerator::Result.new(
              stdout: "",
              stderr: "",
              thread_id: nil,
              output_path: nil
            )
          end
        end
      end

      queue = RepositoryUpdateQueue.new(
        catalog: catalog,
        logger: @logger,
        generator_factory: generator_factory
      )

      first = queue.enqueue(organization: "alpha", repository: "one")
      second = queue.enqueue(organization: "beta", repository: "two")

      assert first
      assert second
      wait_for(timeout: 2) { order.length == 2 ? order.dup : nil }
      assert_equal ["alpha/one", "beta/two"], order
    ensure
      queue&.shutdown
    end

    private

    def wait_for_queue_value(queue, timeout: 2)
      Timeout.timeout(timeout) { queue.pop }
    end

    def wait_until_idle(queue, timeout: 2)
      wait_for(timeout: timeout) do
        status = queue.status
        status[:active_job].nil? && status[:jobs].empty? && status[:size].zero? ? true : nil
      end
    end

    def wait_for(timeout: 2, interval: 0.01)
      Timeout.timeout(timeout) do
        loop do
          value = yield
          return value unless value.nil?
          sleep interval
        end
      end
    end
  end
end
