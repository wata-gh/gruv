# frozen_string_literal: true

require "stringio"

require_relative "test_helper"

module UpdateViewer
  class RepositoryUpdateQueueTest < Minitest::Test
    def setup
      @logger_io = StringIO.new
      @logger = Logger.new(@logger_io)
    end

    def test_enqueue_processes_job_successfully
      recorded_paths = []
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

      result = queue.enqueue(organization: "octocat", repository: "hello-world")

      assert_equal :ok, result.status
      assert_equal generator_result, result.generator_result
      assert_equal "octocat", result.organization
      assert_equal "hello-world", result.repository
      assert_equal ["/tmp/generated.md"], recorded_paths
    ensure
      queue&.shutdown
    end

    def test_enqueue_returns_execution_error_when_generator_fails
      catalog = Object.new
      catalog.define_singleton_method(:register_summary_from_path) do |_path|
        flunk "register_summary_from_path should not be called when generator fails"
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

      result = queue.enqueue(organization: "octocat", repository: "broken")

      assert_equal :execution_error, result.status
      assert_same execution_error, result.error
      assert_nil result.generator_result
    ensure
      queue&.shutdown
    end

    def test_enqueue_returns_registration_error_when_catalog_update_fails
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

      result = queue.enqueue(organization: "octocat", repository: "failing")

      assert_equal :registration_error, result.status
      assert_same generator_result, result.generator_result
      assert_same registration_error, result.error
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

      assert_equal :ok, first.status
      assert_equal :ok, second.status
      assert_equal ["alpha/one", "beta/two"], order
    ensure
      queue&.shutdown
    end
  end
end
