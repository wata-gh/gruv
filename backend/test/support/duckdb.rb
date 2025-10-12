# frozen_string_literal: true

module DuckDB
  class Error < StandardError; end

  class Database
    def self.open(_path)
      new
    end

    def connect
      Connection.new
    end
  end

  class Result
    def initialize(rows = [], columns = nil)
      @rows = rows
      @columns = columns || derive_columns(rows)
    end

    def each(hash: false)
      if hash
        @rows.each { |row| yield(stringify_keys(row)) }
      else
        @rows.each do |row|
          yield(columns.map { |column| value_for(row, column) })
        end
      end
    end

    def columns
      @columns
    end

    private

    attr_reader :rows

    def derive_columns(rows)
      first = rows.first
      return [] unless first

      first.keys.map(&:to_s)
    end

    def stringify_keys(row)
      row.each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = value
      end
    end

    def value_for(row, column)
      row[column] || row[column.to_sym] || row[column.to_s]
    end
  end

  class Connection
    def initialize
      @repositories = []
      @summaries = []
      @next_repository_id = 1
    end

    def execute(sql, *bindings)
      case sql
      when /CREATE TABLE/i, /CREATE SEQUENCE/i, /ALTER SEQUENCE/i
        Result.new
      when /PRAGMA table_info\('repositories'\)/i
        Result.new([
          { name: "id", dflt_value: nil },
          { name: "organization", dflt_value: nil },
          { name: "name", dflt_value: nil }
        ])
      when /ALTER TABLE repositories ALTER COLUMN id SET DEFAULT/i
        raise Error, "already has default"
      when /INSERT INTO repositories \(organization, name\) VALUES \(\?, \?\)/i
        organization, name = bindings
        insert_repository(organization, name)
        Result.new
      when /SELECT id FROM repositories WHERE lower\(organization\) = lower\(\?\) AND lower\(name\) = lower\(\?\) LIMIT 1/i
        organization, name = bindings
        repository = find_repository_case_insensitive(organization, name)
        rows = repository ? [{ id: repository[:id] }] : []
        Result.new(rows)
      when /SELECT id FROM repositories WHERE organization = \? AND name = \? LIMIT 1/i
        organization, name = bindings
        repository = find_repository_exact(organization, name)
        rows = repository ? [{ id: repository[:id] }] : []
        Result.new(rows)
      when /SELECT COUNT\(\*\) AS count FROM repositories/i
        Result.new([{ count: @repositories.count }])
      when /SELECT\s+organization,\s+name\s+FROM\s+repositories\s+ORDER BY\s+lower\(organization\),\s+lower\(name\)/i
        rows = @repositories
               .sort_by { |repo| [repo[:organization].downcase, repo[:name].downcase] }
               .map { |repo| { organization: repo[:organization], name: repo[:name] } }
        Result.new(rows)
      when /FROM\s+summaries\s+s\s+JOIN\s+repositories\s+r/i
        execute_summary_query(sql, *bindings)
      when /SELECT COALESCE\(MAX\(id\), 0\) AS max_id FROM repositories/i
        max_id = @repositories.map { |repo| repo[:id] }.max || 0
        Result.new([{ max_id: max_id }])
      when /INSERT OR REPLACE INTO summaries/i
        repository_id, summary_date, filename, relative_path = bindings
        upsert_summary(repository_id, summary_date, filename, relative_path)
        Result.new
      else
        raise ArgumentError, "Unsupported SQL in DuckDB stub: #{sql}"
      end
    end

    def close; end

    private

    def insert_repository(organization, name)
      repository = find_repository_case_insensitive(organization, name)
      return repository[:id] if repository

      id = @next_repository_id
      @next_repository_id += 1
      @repositories << { id: id, organization: organization, name: name }
      id
    end

    def find_repository_case_insensitive(organization, name)
      @repositories.find do |repo|
        repo[:organization].casecmp?(organization) && repo[:name].casecmp?(name)
      end
    end

    def find_repository_exact(organization, name)
      @repositories.find do |repo|
        repo[:organization] == organization && repo[:name] == name
      end
    end

    def upsert_summary(repository_id, summary_date, filename, relative_path)
      @summaries.reject! do |summary|
        summary[:repository_id] == repository_id && summary[:summary_date] == summary_date
      end
      @summaries << {
        repository_id: repository_id,
        summary_date: summary_date,
        filename: filename,
        relative_path: relative_path
      }
    end

    def execute_summary_query(sql, *bindings)
      case sql
      when /WHERE lower\(r.organization\) = lower\(\?\)\s+AND lower\(r.name\) = lower\(\?\)\s+ORDER BY s.summary_date DESC/i
        organization, repository_name = bindings
        repository = find_repository_case_insensitive(organization, repository_name)
        summaries = if repository
                      summaries_for_repository(repository[:id])
                    else
                      []
                    end
        rows = summaries
               .sort_by { |summary| summary[:summary_date] }
               .reverse
               .map do |summary|
                 {
                   organization: repository ? repository[:organization] : organization,
                   name: repository ? repository[:name] : repository_name,
                   summary_date: summary[:summary_date],
                   filename: summary[:filename],
                   relative_path: summary[:relative_path]
                 }
               end
        Result.new(rows)
      when /WHERE lower\(r.organization\) = lower\(\?\)\s+AND lower\(r.name\) = lower\(\?\)\s+AND s.summary_date = \?\s+LIMIT 1/i
        organization, repository_name, date = bindings
        repository = find_repository_case_insensitive(organization, repository_name)
        summary = if repository
                    summaries_for_repository(repository[:id]).find { |row| row[:summary_date] == date }
                  end
        rows = if summary && repository
                 [{
                   organization: repository[:organization],
                   name: repository[:name],
                   summary_date: summary[:summary_date],
                   filename: summary[:filename],
                   relative_path: summary[:relative_path]
                 }]
               else
                 []
               end
        Result.new(rows)
      else
        # repository_overview query
        rows = @summaries.map do |summary|
          repository = find_repository_exact_by_id(summary[:repository_id])
          next unless repository

          {
            organization: repository[:organization],
            name: repository[:name],
            summary_date: summary[:summary_date],
            filename: summary[:filename],
            relative_path: summary[:relative_path]
          }
        end.compact
        Result.new(rows)
      end
    end

    def summaries_for_repository(repository_id)
      @summaries.select { |summary| summary[:repository_id] == repository_id }
    end

    def find_repository_exact_by_id(id)
      @repositories.find { |repo| repo[:id] == id }
    end
  end
end
