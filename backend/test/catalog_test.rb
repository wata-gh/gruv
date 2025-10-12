# frozen_string_literal: true

require_relative "test_helper"

module UpdateViewer
  class CatalogTest < Minitest::Test
    def setup
      super
      @tmpdir = Dir.mktmpdir("update_viewer-catalog-test")
      @database = Database.new(path: File.join(@tmpdir, "test.duckdb"))
    end

    def teardown
      close_database(@database)
      remove_tmpdir(@tmpdir)
      super
    end

    def test_history_returns_entries_for_registered_summaries
      write_markdown("acme_widgets_2024-03-15.md", "# Old summary")
      write_markdown("acme_widgets_2024-03-16.md", "# New summary")

      catalog = Catalog.new(root: @tmpdir, database: @database)
      history = catalog.history("acme", "widgets")

      assert_equal 2, history.length
      assert_equal Date.new(2024, 3, 16), history.first.date
      assert File.exist?(history.first.path)

      entry = catalog.entry_for("acme", "widgets", "2024-03-15")
      assert_equal Date.new(2024, 3, 15), entry.date
      assert_includes catalog.html_for(entry), "<h1"
    end

    def test_register_summary_from_path_ignores_non_matching_files
      catalog = Catalog.new(root: @tmpdir, database: @database)
      invalid_path = write_markdown("notes.md", "# Ignore")

      result = catalog.register_summary_from_path(invalid_path)
      assert_nil result

      assert_raises(NotFound) do
        catalog.history("acme", "widgets")
      end
    end

    def test_latest_entry_raises_for_missing_repository
      catalog = Catalog.new(root: @tmpdir, database: @database)

      assert_raises(NotFound) do
        catalog.latest_entry("acme", "widgets")
      end
    end

    private

    def write_markdown(filename, contents)
      path = File.join(@tmpdir, filename)
      File.write(path, contents)
      path
    end
  end
end
