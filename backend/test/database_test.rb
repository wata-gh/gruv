# frozen_string_literal: true

require_relative "test_helper"

module UpdateViewer
  class DatabaseTest < Minitest::Test
    def setup
      super
      @tmpdir = Dir.mktmpdir("update_viewer-database-test")
      @database = Database.new(path: File.join(@tmpdir, "test.duckdb"))
    end

    def teardown
      close_database(@database)
      remove_tmpdir(@tmpdir)
      super
    end

    def test_store_summary_persists_and_retrieves_records
      store_summary(
        organization: "acme",
        repository: "widgets",
        date: Date.new(2024, 3, 15),
        filename: "acme_widgets_2024-03-15.md",
        relative_path: "acme/acme_widgets_2024-03-15.md"
      )

      store_summary(
        organization: "acme",
        repository: "widgets",
        date: Date.new(2024, 3, 16),
        filename: "acme_widgets_2024-03-16.md",
        relative_path: "acme/acme_widgets_2024-03-16.md"
      )

      overview = @database.repository_overview
      assert_equal 1, overview.length

      repository = overview.first
      assert_equal "acme", repository[:organization]
      assert_equal "widgets", repository[:repository]
      assert_equal Date.new(2024, 3, 16), repository[:latest_date]
      assert_equal "acme_widgets_2024-03-16.md", repository[:latest_filename]
      assert_equal [Date.new(2024, 3, 16), Date.new(2024, 3, 15)], repository[:available_dates]

      history = @database.history("ACME", "WIDGETS")
      assert_equal 2, history.length
      assert_equal Date.new(2024, 3, 16), history.first[:date]
      assert_equal "acme/acme_widgets_2024-03-16.md", history.first[:relative_path]

      summary = @database.find_summary("acme", "widgets", Date.new(2024, 3, 15))
      refute_nil summary
      assert_equal "acme_widgets_2024-03-15.md", summary[:filename]

      refute @database.empty?
    end

    private

    def store_summary(**attributes)
      @database.store_summary(**attributes)
    end
  end
end
