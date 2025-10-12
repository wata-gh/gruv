# frozen_string_literal: true

require 'date'
require 'json'
require 'logger'
require 'open3'
require 'pathname'
require 'roda'
require 'redcarpet'
require 'time'
require 'duckdb'
require 'fileutils'

module UpdateViewer
  class << self
    def logger
      @logger ||= build_logger
    end

    private

    def build_logger
      logger = Logger.new($stderr)
      logger.level = log_level_from_env
      logger.formatter = proc do |severity, datetime, progname, msg|
        timestamp = datetime.utc.iso8601
        label = progname ? "[#{progname}] " : ''
        payload = msg.is_a?(String) ? msg : msg.inspect
        "#{timestamp} #{severity.ljust(5)} #{label}#{payload}\n"
      end
      logger
    end

    def log_level_from_env
      level_name = ENV.fetch('LOG_LEVEL', 'INFO').to_s.upcase
      Logger.const_get(level_name)
    rescue NameError
      Logger::INFO
    end
  end

  class NotFound < StandardError; end

  Entry = Struct.new(:organization, :repository, :date, :path, keyword_init: true) do
    def identifier
      {
        organization: organization,
        repository: repository,
        date: date,
        filename: File.basename(path)
      }
    end
  end

  class SummaryGenerator
    class ExecutionError < StandardError
      attr_reader :stdout, :stderr, :status

      def initialize(message, stdout:, stderr:, status:)
        super(message)
        @stdout = stdout
        @stderr = stderr
        @status = status
      end
    end

    SCRIPT_PATH = File.expand_path('../scripts/generate_summary.mjs', __dir__)
    REPOSITORY_ROOT = File.expand_path('..', __dir__)

    Result = Struct.new(:stdout, :stderr, :thread_id, :output_path, keyword_init: true)

    def initialize(organization, repository)
      @organization = organization
      @repository = repository
    end

    def call
      validate_inputs!
      ensure_script_presence!

      stdout, stderr, status = Open3.capture3('node', SCRIPT_PATH, organization, repository, chdir: REPOSITORY_ROOT)

      unless status.success?
        raise ExecutionError.new('Summary generation failed', stdout: stdout, stderr: stderr, status: status.exitstatus)
      end

      Result.new(
        stdout: stdout,
        stderr: stderr,
        thread_id: extract_thread_id(stdout),
        output_path: extract_output_path(stdout)
      )
    end

    private

    attr_reader :organization, :repository

    def validate_inputs!
      if organization.to_s.strip.empty? || repository.to_s.strip.empty?
        raise ArgumentError, 'organization and repository must be provided'
      end
    end

    def ensure_script_presence!
      return if File.exist?(SCRIPT_PATH)

      raise ExecutionError.new('Summary helper script not found', stdout: '', stderr: "Missing script at #{SCRIPT_PATH}", status: -1)
    end

    def extract_thread_id(stdout)
      stdout.lines.find { |line| line.start_with?('Thread ID:') }&.split(':', 2)&.last&.strip
    end

    def extract_output_path(stdout)
      stdout.lines.find { |line| line.start_with?('Summary written to') }&.split('Summary written to', 2)&.last&.strip
    end
  end

  class Database
    DEFAULT_DB_PATH = File.expand_path('../data/update_viewer.duckdb', __dir__).freeze

    def initialize(path: ENV.fetch('UPDATE_VIEWER_DATABASE', DEFAULT_DB_PATH))
      @path = path
      ensure_directory
      @connection = DuckDB::Database.open(path).connect
      setup_schema
    end

    def repository_overview
      repositories = query(<<~SQL)
        SELECT organization, name
        FROM repositories
        ORDER BY lower(organization), lower(name)
      SQL

      summaries = query(<<~SQL)
        SELECT r.organization, r.name, s.summary_date, s.filename
        FROM summaries s
        JOIN repositories r ON r.id = s.repository_id
      SQL

      grouped = summaries.group_by { |row| [row['organization'], row['name']] }

      repositories.map do |row|
        key = [row['organization'], row['name']]
        summary_rows = Array(grouped[key]).sort_by { |summary| parse_date(summary['summary_date']) }.reverse
        latest = summary_rows.first

        {
          organization: row['organization'],
          repository: row['name'],
          latest_date: latest && parse_date(latest['summary_date']),
          latest_filename: latest && latest['filename'],
          available_dates: summary_rows.map { |summary| parse_date(summary['summary_date']) }
        }
      end
    end

    def history(organization, repository)
      sql = <<~SQL
        SELECT
          r.organization,
          r.name,
          s.summary_date,
          s.filename,
          s.relative_path
        FROM summaries s
        JOIN repositories r ON r.id = s.repository_id
        WHERE lower(r.organization) = lower(?)
          AND lower(r.name) = lower(?)
        ORDER BY s.summary_date DESC
      SQL

      query(sql, organization, repository).map do |row|
        summary_record(row)
      end
    end

    def find_summary(organization, repository, date)
      sql = <<~SQL
        SELECT
          r.organization,
          r.name,
          s.summary_date,
          s.filename,
          s.relative_path
        FROM summaries s
        JOIN repositories r ON r.id = s.repository_id
        WHERE lower(r.organization) = lower(?)
          AND lower(r.name) = lower(?)
          AND s.summary_date = ?
        LIMIT 1
      SQL

      row = query(sql, organization, repository, date).first
      row && summary_record(row)
    end

    def store_summary(organization:, repository:, date:, filename:, relative_path:)
      repo_id = ensure_repository(organization, repository)
      sql = <<~SQL
        INSERT OR REPLACE INTO summaries (repository_id, summary_date, filename, relative_path)
        VALUES (?, ?, ?, ?)
      SQL
      execute(sql, repo_id, date, filename, relative_path)
    end

    def empty?
      repository_count.zero?
    end

    private

    attr_reader :connection, :path

    def summary_record(row)
      {
        organization: row['organization'],
        repository: row['name'],
        date: parse_date(row['summary_date']),
        filename: row['filename'],
        relative_path: row['relative_path']
      }
    end

    def ensure_repository(organization, repository)
      existing = query(
        'SELECT id FROM repositories WHERE lower(organization) = lower(?) AND lower(name) = lower(?) LIMIT 1',
        organization,
        repository
      ).first

      return existing['id'] if existing

      execute('INSERT INTO repositories (organization, name) VALUES (?, ?)', organization, repository)
      query(
        'SELECT id FROM repositories WHERE organization = ? AND name = ? LIMIT 1',
        organization,
        repository
      ).first.fetch('id')
    end

    def repository_count
      query('SELECT COUNT(*) AS count FROM repositories').first.fetch('count', 0).to_i
    end

    def ensure_directory
      FileUtils.mkdir_p(File.dirname(path))
    end

    def setup_schema
      execute(<<~SQL)
        CREATE SEQUENCE IF NOT EXISTS repositories_id_seq START 1;
      SQL

      execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS repositories (
          id BIGINT PRIMARY KEY DEFAULT nextval('repositories_id_seq'),
          organization TEXT NOT NULL,
          name TEXT NOT NULL,
          UNIQUE (organization, name)
        )
      SQL

      ensure_repository_id_default
      synchronize_repository_sequence

      execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS summaries (
          repository_id BIGINT NOT NULL,
          summary_date DATE NOT NULL,
          filename TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (repository_id, summary_date)
        )
      SQL
    end

    def execute(sql, *bindings)
      connection.execute(sql, *bindings)
    end

    def ensure_repository_id_default
      info = query("PRAGMA table_info('repositories')")
      id_column = info.find { |column| column['name'] == 'id' }
      return unless id_column

      default_value = id_column['dflt_value'].to_s
      return unless default_value.strip.empty?

      execute(<<~SQL)
        ALTER TABLE repositories ALTER COLUMN id SET DEFAULT nextval('repositories_id_seq')
      SQL
    rescue DuckDB::Error => e
      raise unless e.message.match?(/already has|duplicate column/i)
    end

    def synchronize_repository_sequence
      max_id_row = query('SELECT COALESCE(MAX(id), 0) AS max_id FROM repositories').first
      max_id = max_id_row ? max_id_row.fetch('max_id', 0).to_i : 0
      execute("ALTER SEQUENCE repositories_id_seq RESTART WITH #{max_id + 1}")
    rescue DuckDB::Error => e
      raise unless e.message.match?(/unknown sequence/i)
    end

    def query(sql, *bindings)
      result = execute(sql, *bindings)
      rows = []

      if supports_result_hash_argument?(result)
        result.each(hash: true) { |row| rows << stringify_keys(row) }
      else
        columns = extract_column_names(result)
        result.each do |row|
          rows << coerce_row(row, columns)
        end
      end

      rows
    end

    def supports_result_hash_argument?(result)
      result.method(:each).parameters.any? { |type, name| type == :key && name == :hash }
    rescue NameError
      false
    end

    def extract_column_names(result)
      return [] unless result.respond_to?(:columns)

      Array(result.columns).map do |column|
        if column.respond_to?(:name)
          column.name.to_s
        else
          column.to_s
        end
      end
    end

    def coerce_row(row, columns)
      case row
      when Hash
        stringify_keys(row)
      else
        hash_row = if row.respond_to?(:to_h)
                     row.to_h
                   elsif columns.empty?
                     {}
                   else
                     columns.each_with_index.each_with_object({}) do |(column, index), hash|
                       hash[column] = row[index]
                     end
                   end

        stringify_keys(hash_row)
      end
    end

    def stringify_keys(row)
      row.each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = value
      end
    end

    def parse_date(value)
      return if value.nil?
      case value
      when Date
        value
      when Time
        value.to_date
      else
        Date.parse(value.to_s)
      end
    end

  end

  class Catalog
    FILENAME_PATTERN = /\A(?<organization>.+?)_(?<repository>.+)_(?<date>\d{4}-\d{2}-\d{2})\.md\z/.freeze

    attr_reader :root, :database

    def initialize(root: ENV.fetch('UPDATES_ROOT', default_root), database: Database.new)
      @root = root
      @database = database
      synchronize_filesystem!
    end

    def repositories
      database.repository_overview.map do |record|
        {
          organization: record[:organization],
          repository: record[:repository],
          latest_date: record[:latest_date],
          latest_filename: record[:latest_filename],
          available_dates: record[:available_dates]
        }
      end
    end

    def latest_entry(organization, repository)
      history(organization, repository).first || raise(NotFound, 'Latest summary not found')
    end

    def history(organization, repository)
      records = database.history(organization, repository)
      raise(NotFound, 'Repository not found') if records.empty?

      records.map { |record| build_entry_from_record(record) }
    end

    def entry_for(organization, repository, date_str)
      date = parse_date(date_str)
      record = database.find_summary(organization, repository, date)
      raise(NotFound, 'Summary not found') unless record

      build_entry_from_record(record)
    end

    def markdown_for(entry)
      File.read(entry.path)
    end

    def html_for(entry)
      markdown_renderer.render(markdown_for(entry))
    end

    def register_summary_from_path(path)
      entry = build_entry(path)
      return unless entry

      database.store_summary(
        organization: entry.organization,
        repository: entry.repository,
        date: entry.date,
        filename: File.basename(path),
        relative_path: relative_path_for(path)
      )

      entry
    end

    private

    def synchronize_filesystem!
      return unless database.empty?

      markdown_paths.each do |path|
        register_summary_from_path(path)
      end
    end

    def default_root
      File.expand_path('..', __dir__)
    end

    def build_entry(path)
      match = FILENAME_PATTERN.match(File.basename(path))
      return unless match

      Entry.new(
        organization: match[:organization],
        repository: match[:repository],
        date: parse_date(match[:date]),
        path: path
      )
    rescue ArgumentError
      nil
    end

    def build_entry_from_record(record)
      Entry.new(
        organization: record[:organization],
        repository: record[:repository],
        date: record[:date],
        path: absolute_path_for(record[:relative_path])
      )
    end

    def absolute_path_for(relative_path)
      File.expand_path(relative_path, root)
    end

    def relative_path_for(path)
      Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
    rescue ArgumentError
      File.basename(path)
    end

    def markdown_paths
      Dir.glob(File.join(root, '*.md')).select { |path| File.file?(path) && path.match?(FILENAME_PATTERN) }
    end

    def parse_date(date_str)
      Date.parse(date_str.to_s)
    end

    def markdown_renderer
      @markdown_renderer ||= begin
        renderer = Redcarpet::Render::HTML.new(with_toc_data: true, hard_wrap: true)
        Redcarpet::Markdown.new(
          renderer,
          autolink: true,
          fenced_code_blocks: true,
          tables: true,
          strikethrough: true,
          underline: true,
          highlight: true,
          quote: true,
          footnotes: true
        )
      end
    end
  end

  class App < Roda
    plugin :all_verbs
    plugin :json, classes: [Array, Hash]
    plugin :error_handler do |error|
      case error
      when NotFound
        UpdateViewer.logger.warn("[app] NotFound path=#{request.path} method=#{request.request_method} message=#{error.message}")
        response.status = 404
        { error: error.message }
      else
        UpdateViewer.logger.error(
          "[app] Unhandled error path=#{request.path} method=#{request.request_method} error=#{error.class}: #{error.message}\n#{Array(error.backtrace).join("\n")}"
        )
        response.status = 500
        { error: 'Internal server error' }
      end
    end

    ROUTE_CACHE_TTL = 5

    def initialize(*args)
      super
      @catalog = Catalog.new
    end

    route do |r|
      r.root do
        {
          name: 'GitHub Repository Update Viewer API',
          version: '1.0',
          endpoints: [
            '/repos',
            '/repos/:organization/:repository/latest',
            '/repos/:organization/:repository/history',
            '/repos/:organization/:repository/:date'
          ]
        }
      end

      r.on 'repos' do
        r.get true do
          { repositories: catalog.repositories }
        end

        r.post 'generate' do
          payload = parse_json_body(r)
          begin
            repo = normalize_repository_reference(payload)
          rescue ArgumentError => e
            response.status = 400
            UpdateViewer.logger.warn(
              "[generate] Invalid repository reference from payload_keys=#{payload.keys.join(',')} error=#{e.message}"
            )
            next({ error: e.message })
          end

          generator = SummaryGenerator.new(repo[:organization], repo[:repository])

          begin
            result = generator.call
          rescue SummaryGenerator::ExecutionError => e
            UpdateViewer.logger.error(
              "[generate] Execution failed for #{repo[:organization]}/#{repo[:repository]} status=#{e.status} stdout=#{sanitize_output(e.stdout)} stderr=#{sanitize_output(e.stderr)}"
            )
            response.status = 500
            next({
              error: e.message,
              stdout: e.stdout.to_s.strip,
              stderr: e.stderr.to_s.strip,
              status: e.status
            })
          rescue ArgumentError => e
            response.status = 400
            UpdateViewer.logger.warn(
              "[generate] Validation error for #{repo[:organization]}/#{repo[:repository]} message=#{e.message}"
            )
            next({ error: e.message })
          end

          if result.output_path
            begin
              catalog.register_summary_from_path(result.output_path)
            rescue StandardError => e
              UpdateViewer.logger.error(
                "[generate] Failed to register summary for #{repo[:organization]}/#{repo[:repository]} path=#{result.output_path} error=#{e.message}"
              )
            end
          end

          response.status = 200
          {
            message: 'Summary generation completed',
            repository: repo,
            output_path: result.output_path,
            output_filename: result.output_path && File.basename(result.output_path),
            thread_id: result.thread_id,
            stdout: result.stdout.to_s.strip,
            stderr: result.stderr.to_s.strip
          }
        end

        r.on String, String do |organization, repository|
          r.get 'latest' do
            entry = catalog.latest_entry(organization, repository)
            serialize_entry(entry)
          end

          r.get 'history' do
            entries = catalog.history(organization, repository)
            {
              repository: {
                organization: entries.first&.organization || organization,
                name: entries.first&.repository || repository
              },
              history: entries.map(&:identifier)
            }
          end

          r.get String do |date|
            entry = catalog.entry_for(organization, repository, date)
            serialize_entry(entry)
          end
        end
      end
    end

    private

    attr_reader :catalog

    def serialize_entry(entry)
      {
        repository: {
          organization: entry.organization,
          name: entry.repository
        },
        summary: {
          date: entry.date,
          filename: File.basename(entry.path),
          markdown: catalog.markdown_for(entry),
          html: catalog.html_for(entry)
        }
      }
    end

    def parse_json_body(request)
      raw = request.body.read.to_s
      request.body.rewind if request.body.respond_to?(:rewind)
      return {} if raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      raise ArgumentError, 'Invalid JSON payload'
    end

    def normalize_repository_reference(payload)
      payload = payload.is_a?(Hash) ? payload : {}
      organization = (payload['organization'] || payload['org'])&.strip
      repository = (payload['repository'] || payload['repo'])&.strip
      url = payload['url']&.strip

      if url && (organization.nil? || organization.empty? || repository.nil? || repository.empty?)
        org_from_url, repo_from_url = parse_repository_url(url)
        organization ||= org_from_url
        repository ||= repo_from_url
      end

      if organization.to_s.empty? || repository.to_s.empty?
        raise ArgumentError, 'organization and repository are required'
      end

      { organization: organization, repository: repository.sub(/\.git\z/i, '') }
    end

    def parse_repository_url(url)
      cleaned = url.to_s.strip
      cleaned = cleaned.sub(/\?.*\z/, '').sub(/#.*\z/, '')
      cleaned = cleaned.sub(/\Ahttps?:\/\//i, '')

      if cleaned.start_with?('github.com/')
        cleaned = cleaned.split('/', 2).last
      end

      parts = cleaned.split('/')
      if parts.size < 2
        raise ArgumentError, 'Invalid GitHub repository URL'
      end

      organization = parts[0]
      repository = parts[1]

      organization = organization.strip
      repository = repository.strip.sub(/\.git\z/i, '')

      if organization.empty? || repository.empty?
        raise ArgumentError, 'Invalid GitHub repository URL'
      end

      [organization, repository]
    end

    def sanitize_output(value, limit: 800)
      text = value.to_s.strip
      return '' if text.empty?
      return text if text.length <= limit

      "#{text[0, limit]}...(truncated)"
    end
  end
end
