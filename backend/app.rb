# frozen_string_literal: true

require 'date'
require 'json'
require 'open3'
require 'roda'
require 'redcarpet'

module UpdateViewer
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

  class Catalog
    FILENAME_PATTERN = /\A(?<organization>.+?)_(?<repository>.+)_(?<date>\d{4}-\d{2}-\d{2})\.md\z/.freeze

    attr_reader :root

    def initialize(root: ENV.fetch('UPDATES_ROOT', default_root))
      @root = root
    end

    def repositories
      grouped_entries.keys.sort_by { |org, repo| [org.downcase, repo.downcase] }.map do |org, repo|
        entries = grouped_entries[[org, repo]].sort_by { |entry| entry.date }.reverse
        latest = entries.first

        {
          organization: org,
          repository: repo,
          latest_date: latest&.date,
          latest_filename: latest && File.basename(latest.path),
          available_dates: entries.map(&:date)
        }
      end
    end

    def latest_entry(organization, repository)
      history(organization, repository).first || raise(NotFound, 'Latest summary not found')
    end

    def history(organization, repository)
      key = normalize_key(organization, repository)
      entries = grouped_entries.fetch(key) { raise(NotFound, 'Repository not found') }
      entries.sort_by(&:date).reverse
    end

    def entry_for(organization, repository, date_str)
      date = parse_date(date_str)
      history(organization, repository).find { |entry| entry.date == date } || raise(NotFound, 'Summary not found')
    end

    def markdown_for(entry)
      File.read(entry.path)
    end

    def html_for(entry)
      markdown_renderer.render(markdown_for(entry))
    end

    private

    def default_root
      File.expand_path('..', __dir__)
    end

    def grouped_entries
      @grouped_entries = nil if cache_stale?
      @grouped_entries ||= build_index
    end

    def cache_stale?
      current_mtime = latest_mtime
      if defined?(@last_mtime)
        current_mtime != @last_mtime
      else
        @last_mtime = current_mtime
        false
      end
    end

    def latest_mtime
      markdown_paths.map { |path| File.mtime(path) }.max
    rescue StandardError
      Time.at(0)
    end

    def markdown_paths
      Dir.glob(File.join(root, '*.md')).select { |path| File.file?(path) && path.match?(FILENAME_PATTERN) }
    end

    def build_index
      index = Hash.new { |hash, key| hash[key] = [] }

      markdown_paths.each do |path|
        entry = build_entry(path)
        next unless entry

        index[[entry.organization, entry.repository]] << entry
      end

      @last_mtime = latest_mtime
      index
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

    def parse_date(date_str)
      Date.parse(date_str)
    end

    def normalize_key(organization, repository)
      grouped_entries.keys.find do |org, repo|
        org.casecmp?(organization) && repo.casecmp?(repository)
      end || [organization, repository]
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
        response.status = 404
        { error: error.message }
      else
        warn "[error] #{error.class}: #{error.message}\n#{error.backtrace.join("\n")}"
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
            next({ error: e.message })
          end

          generator = SummaryGenerator.new(repo[:organization], repo[:repository])

          begin
            result = generator.call
          rescue SummaryGenerator::ExecutionError => e
            response.status = 500
            next({
              error: e.message,
              stdout: e.stdout.to_s.strip,
              stderr: e.stderr.to_s.strip,
              status: e.status
            })
          rescue ArgumentError => e
            response.status = 400
            next({ error: e.message })
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
  end
end
