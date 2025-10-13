#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'date'
require 'pathname'

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../backend/Gemfile', __dir__)
require 'bundler/setup'

require_relative '../backend/app'

module UpdateViewer
  module Scripts
    class MarkdownMigrator
      DEFAULT_ROOT = File.expand_path('..', __dir__).freeze

      def initialize(root:, database_path:, dry_run: false, verbose: true)
        @root = root
        @database_path = database_path
        @dry_run = dry_run
        @verbose = verbose
        @database = UpdateViewer::Database.new(path: database_path)
      end

      def run
        markdown_paths = discover_markdown_paths
        if markdown_paths.empty?
          log('No markdown files matching the expected pattern were found. Nothing to migrate.')
          return
        end

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
      end

      private

      attr_reader :root, :database_path, :database, :dry_run, :verbose

      def dry_run?
        dry_run
      end

      def discover_markdown_paths
        Dir.glob(File.join(root, '**', '*.md'))
           .select { |path| File.file?(path) && filename_matches?(File.basename(path)) }
           .sort
      end

      def filename_matches?(filename)
        !!UpdateViewer::Catalog::FILENAME_PATTERN.match(filename)
      end

      def build_record(path)
        match = UpdateViewer::Catalog::FILENAME_PATTERN.match(File.basename(path))
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
    end

    def self.parse_arguments(argv)
      options = {
        root: MarkdownMigrator::DEFAULT_ROOT,
        database_path: UpdateViewer::Database::DEFAULT_DB_PATH,
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
