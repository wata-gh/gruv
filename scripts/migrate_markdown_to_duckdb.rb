#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'date'
require 'pathname'

module UpdateViewer
  module Scripts
    class MarkdownMigrator
      DEFAULT_ROOT = File.expand_path('..', __dir__).freeze
      DEFAULT_DATABASE_PATH = File.expand_path('../backend/data/update_viewer.duckdb', __dir__).freeze
      FILENAME_PATTERN = /\A(?<organization>.+?)_(?<repository>.+)_(?<date>\d{4}-\d{2}-\d{2})\.md\z/.freeze

      class MissingDependenciesError < StandardError; end

      def initialize(root:, database_path:, dry_run: false, verbose: true)
        @root = root
        @database_path = database_path
        @dry_run = dry_run
        @verbose = verbose
      end

      def run
        markdown_paths = discover_markdown_paths
        if markdown_paths.empty?
          log('No markdown files matching the expected pattern were found. Nothing to migrate.')
          return
        end

        ensure_backend_loaded unless dry_run?

        migrated = 0
        skipped = []

        markdown_paths.each do |path|
          record = build_record(path)
          unless record
            skipped << path
            next
          end

          if dry_run?
            log("[DRY RUN] Would migrate #{record_description(record)}")
            migrated += 1
            next
          end

          database.store_summary(**record)
          log("Migrated #{record_description(record)}")
          migrated += 1
        rescue StandardError => e
          skipped << path
          warn("Failed to migrate #{path}: #{e.class} - #{e.message}")
        end

        log('--- Migration complete ---')
        log("Processed files: #{markdown_paths.size}")
        log("Migrated entries: #{migrated}")
        if skipped.any?
          log("Skipped files (#{skipped.size}):")
          skipped.each { |path| log("  - #{relative_to_root(path)}") }
        end
      rescue MissingDependenciesError => e
        warn(e.message)
        exit(1)
      end

      private

      attr_reader :root, :database_path, :dry_run, :verbose

      def dry_run?
        dry_run
      end

      def discover_markdown_paths
        Dir.glob(File.join(root, '**', '*.md'))
           .select { |path| File.file?(path) && filename_matches?(File.basename(path)) }
           .sort
      end

      def filename_matches?(filename)
        !!FILENAME_PATTERN.match(filename)
      end

      def build_record(path)
        match = FILENAME_PATTERN.match(File.basename(path))
        return unless match

        date = Date.parse(match[:date])
        {
          organization: match[:organization],
          repository: match[:repository],
          date: date,
          filename: File.basename(path),
          relative_path: relative_to_root(path)
        }
      rescue ArgumentError
        nil
      end

      def relative_to_root(path)
        Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
      rescue ArgumentError
        File.basename(path)
      end

      def log(message)
        return unless verbose

        puts(message)
      end

      def record_description(record)
        "#{record[:organization]}/#{record[:repository]} @ #{record[:date]} (#{record[:relative_path]})"
      end

      def database
        @database ||= begin
          ensure_backend_loaded
          UpdateViewer::Database.new(path: database_path)
        end
      end

      def ensure_backend_loaded
        return if @backend_loaded

        require_backend
        @backend_loaded = true
      rescue LoadError => e
        raise MissingDependenciesError, "Failed to load backend dependencies: #{e.message}"
      end

      def require_backend
        require_relative '../backend/app'
      rescue LoadError
        setup_bundler_and_require
      end

      def setup_bundler_and_require
        ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../backend/Gemfile', __dir__)
        require 'bundler'
        Bundler.ui = Bundler::UI::Silent.new if defined?(Bundler::UI::Silent)
        Bundler.setup
        require_relative '../backend/app'
      rescue Bundler::GemNotFound => e
        raise MissingDependenciesError, <<~MESSAGE.strip
          Missing gems for the backend: #{e.message}. Run `bundle install --gemfile backend/Gemfile` before executing the migration.
        MESSAGE
      rescue SystemExit
        raise MissingDependenciesError, 'Missing gems for the backend. Run `bundle install --gemfile backend/Gemfile` before executing the migration.'
      end
    end

    def self.parse_arguments(argv)
      options = {
        root: MarkdownMigrator::DEFAULT_ROOT,
        database_path: MarkdownMigrator::DEFAULT_DATABASE_PATH,
        dry_run: false,
        verbose: true
      }

      parser = OptionParser.new do |opts|
        opts.banner = 'Usage: ruby scripts/migrate_markdown_to_duckdb.rb [options]'

        opts.on('-r', '--root PATH', 'Root directory that contains markdown summaries (default: repo root)') do |value|
          options[:root] = File.expand_path(value)
        end

        opts.on('-d', '--database PATH', 'Path to the DuckDB database file (default: backend/data/update_viewer.duckdb)') do |value|
          options[:database_path] = File.expand_path(value)
        end

        opts.on('--dry-run', 'Simulate the migration without writing to the database') do
          options[:dry_run] = true
        end

        opts.on('--no-verbose', 'Suppress progress output') do
          options[:verbose] = false
        end

        opts.on('-h', '--help', 'Show this help message') do
          puts opts
          exit
        end
      end

      parser.parse!(argv)
      options
    end

    def self.run(argv = ARGV)
      options = parse_arguments(argv)
      migrator = MarkdownMigrator.new(**options)
      migrator.run
    end
  end
end

if $PROGRAM_NAME == __FILE__
  UpdateViewer::Scripts.run
end
