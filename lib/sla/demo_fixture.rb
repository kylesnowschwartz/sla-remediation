# frozen_string_literal: true

require 'json'
require 'time'

require_relative 'errors'
require_relative 'status_page'

module SLA
  # Moves the findings and sessions tables between the database and a JSON
  # file, so a status page can be filled from a captured run without any
  # credentials. `export` writes every row of both tables with timestamps as
  # ISO 8601 UTC strings; `load` reads them back, shifting every timestamp
  # forward by one amount so the newest check or merge time lands at load
  # time and every interval between events is kept.
  class DemoFixture
    TABLES = %i[findings sessions].freeze
    ANCHOR_COLUMNS = %i[pr_checks_at pr_merged_at].freeze
    NOTE = 'Rows of the findings and sessions tables from one run of the demo against the fork, ' \
           'for bin/demo-load. Nothing here is secret: issue numbers, package names, session ids, ' \
           'pull request URLs and check states.'

    # Raised by `load` when a table already has rows and `replace` was not asked for.
    class DatabaseNotEmpty < Error; end

    def initialize(db, out: $stdout)
      @db = db
      @out = out
    end

    # Both tables as a Hash ready for JSON: a note with the export time, then
    # every row of each table with Time values as ISO 8601 UTC strings.
    def export(now: Time.now.utc)
      exported_at = now.utc.iso8601
      fixture = { 'note' => "#{NOTE} Exported #{exported_at}.", 'exported_at' => exported_at }
      TABLES.each do |table|
        rows = @db[table].order(:id).all.map { |row| stringify(row) }
        fixture[table.to_s] = rows
        @out.puts "exported #{rows.size} #{table}"
      end
      fixture
    end

    # Inserts the fixture's rows, timestamps shifted so the newest check or
    # merge time is `now`. Refuses when either table has rows unless
    # `replace`, which empties both first. Returns the counts and the shift.
    def load(fixture, now: Time.now.utc, replace: false)
      rows = TABLES.to_h { |table| [table, parse_rows(fixture, table)] }
      shift = shift_for(rows, now.utc)
      @db.transaction do
        clear_or_refuse(replace)
        insert(rows, shift)
      end
      @out.puts "shifted every timestamp forward by #{StatusPage.duration(shift)}"
      { findings: rows[:findings].size, sessions: rows[:sessions].size, shift_seconds: shift.round }
    end

    private

    def datetime_columns(table)
      @db.schema(table).filter_map { |column, info| column if info[:type] == :datetime }
    end

    def stringify(row)
      row.transform_values { |value| value.is_a?(Time) ? value.utc.iso8601(6) : value }
    end

    def parse_rows(fixture, table)
      columns = datetime_columns(table)
      Array(fixture[table.to_s]).map do |row|
        row.to_h do |column, value|
          column = column.to_sym
          [column, columns.include?(column) && value ? Time.iso8601(value) : value]
        end
      end
    end

    # Seconds from the newest check or merge time in the fixture to `now`;
    # with no checks or merges recorded, from the newest timestamp of any kind.
    def shift_for(rows, now)
      anchor = newest(rows[:sessions], ANCHOR_COLUMNS) ||
               newest(rows.values.flatten, TABLES.flat_map { |table| datetime_columns(table) })
      anchor ? now - anchor : 0.0
    end

    def newest(rows, columns)
      rows.flat_map { |row| row.values_at(*columns) }.compact.max
    end

    def insert(rows, shift)
      TABLES.each do |table|
        @db[table].multi_insert(shifted(rows[table], table, shift))
        @out.puts "loaded #{rows[table].size} #{table}"
      end
    end

    def shifted(rows, table, shift)
      columns = datetime_columns(table)
      rows.map do |row|
        row.to_h { |column, value| [column, columns.include?(column) && value ? value + shift : value] }
      end
    end

    def clear_or_refuse(replace)
      counts = TABLES.to_h { |table| [table, @db[table].count] }
      return if counts.values.sum.zero?

      unless replace
        raise DatabaseNotEmpty,
              "database already has #{counts[:findings]} findings and #{counts[:sessions]} sessions; " \
              'pass --replace to empty both tables first'
      end

      @db[:sessions].delete
      @db[:findings].delete
      @out.puts "deleted #{counts[:sessions]} sessions and #{counts[:findings]} findings"
    end
  end
end
