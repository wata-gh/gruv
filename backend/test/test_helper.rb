# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift(File.expand_path("support", __dir__))

require_relative "../app"

module UpdateViewerTestHelpers
  def close_database(database)
    return unless database

    connection = database.instance_variable_get(:@connection)
    return unless connection

    connection.close if connection.respond_to?(:close)
  rescue StandardError
    # Ignore errors when closing the DuckDB connection to avoid masking test results.
  end

  def remove_tmpdir(path)
    return unless path && File.directory?(path)

    FileUtils.remove_entry(path)
  end
end

Minitest::Test.include(UpdateViewerTestHelpers)
