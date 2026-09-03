# frozen_string_literal: true

require 'json'
require 'sequel'

require_relative 'notifier'
require_relative 'tracker'

module SLA
  # Everything the status page shows, worked out from the findings and sessions
  # tables: one Row per finding with its SLA word and every string formatted,
  # and the four summary counts. The template only prints what is here.
  class StatusPage
    SEVERITY_ORDER = %w[critical high medium low].freeze
    TIME_FORMAT = Notifier::DUE_AT_FORMAT
    NONE = '—'
    NOT_YET = 'not yet'
    SESSION_COLUMNS = %i[devin_session_id status status_detail acus_consumed pr_url pr_state outcome started_at
                         pr_notified_at pr_checks pr_checks_at pr_merged_at structured_output
                         structured_output_invalid].freeze

    Summary = Struct.new(:findings, :fixed_inside_sla, :breached, :median_time_to_green,
                         keyword_init: true)

    # One finding left-joined to its session, as the table prints it.
    class Row
      NOT_DISPATCHED = 'not dispatched'
      NOT_REPORTED = 'not reported'
      NO_FIX = 'no fix'
      REPORT_REJECTED = 'report rejected (schema)'
      BREACHED_WORDS = %w[breached late].freeze

      attr_reader :record, :now

      def initialize(record, now:)
        @record = record
        @now = now
      end

      %i[issue_number issue_url issue_title package pinned fix_version severity pr_url pr_state source
         ecosystem devin_session_id].each do |column|
        define_method(column) { record[column] }
      end

      def versions
        "#{record[:pinned]} → #{record[:fix_version] || NO_FIX}"
      end

      def fix_version?
        !record[:fix_version].nil?
      end

      def no_fix_text
        NO_FIX
      end

      def filed
        StatusPage.time(record[:created_at])
      end

      def due
        StatusPage.time(record[:due_at])
      end

      def due_in
        remaining = record[:due_at] - now
        remaining.negative? ? "#{StatusPage.duration(-remaining)} ago" : "in #{StatusPage.duration(remaining)}"
      end

      def overdue?
        breached?
      end

      def sla
        @sla ||= sla_word
      end

      def sla_class
        "sla-#{sla.tr(' ', '-')}"
      end

      def sla_tag
        "[#{sla.upcase}]"
      end

      def toggle_id
        "f#{issue_number}"
      end

      def breached?
        BREACHED_WORDS.include?(sla)
      end

      def devin
        return NOT_DISPATCHED unless session?

        record[:outcome] || status_line
      end

      def devin_url
        "#{Notifier::SESSION_URL}/#{record[:devin_session_id]}" if record[:devin_session_id]
      end

      def pr_number
        pr_url&.split('/')&.last
      end

      def time_to_pr
        return nil unless record[:started_at] && record[:pr_notified_at]

        StatusPage.duration(record[:pr_notified_at] - record[:started_at])
      end

      # The check state as GitHubClient reports it (`pending`, `failure`,
      # `success`, or `none`), or nil before the tracker has observed any.
      def checks
        record[:pr_checks]
      end

      def checks?
        !record[:pr_checks].nil?
      end

      # When the checks (or the merge) were last observed, formatted for the
      # template.
      def checks_observed_at
        StatusPage.time(record[:pr_merged_at] || record[:pr_checks_at])
      end

      # When the pull request turned green: its merge time, else the time its
      # checks last completed while they are passing (a later push that goes
      # green again moves this forward), or nil while it has not.
      def green_at
        record[:pr_merged_at] || (record[:pr_checks] == 'success' ? record[:pr_checks_at] : nil)
      end

      # Seconds from the session's start to the pull request turning green, or
      # nil when either time is missing.
      def seconds_to_green
        return nil unless record[:started_at] && green_at

        green_at - record[:started_at]
      end

      def acus
        acus_reported? ? record[:acus_consumed].to_s : NOT_REPORTED
      end

      def acus_reported?
        acus_consumed = record[:acus_consumed]
        !(acus_consumed.nil? || acus_consumed.zero?)
      end

      # "running/finished → settled", or just "running/finished" before the
      # session has closed.
      def session_status
        record[:outcome] ? "#{status_line} → #{record[:outcome]}" : status_line
      end

      def started
        record[:started_at] && StatusPage.time(record[:started_at])
      end

      def advisories
        return nil unless record[:advisories]

        list = JSON.parse(record[:advisories])
        list.empty? ? nil : list.join(', ')
      end

      # The verification the session reported on its structured output: nil
      # before a session has reported one, and REPORT_REJECTED when the report
      # it sent failed schema validation.
      def lockfile
        return REPORT_REJECTED if record[:structured_output].nil? && record[:structured_output_invalid]
        return nil unless record[:structured_output]

        report = JSON.parse(record[:structured_output])
        verification = report['verification'] || {}
        "#{report['lockfile_route']} · #{verification['tool']} #{verification['clean'] ? 'clean' : 'not clean'}"
      end

      def session?
        !record[:session_row_id].nil?
      end

      private

      def status_line
        record.values_at(:status, :status_detail).compact.join('/')
      end

      def sla_word
        due_at = record[:due_at]
        if pr_url
          pr_sla_word(due_at)
        elsif now > due_at then 'breached'
        elsif record[:outcome] == Tracker::STALLED then 'stalled'
        elsif session? then 'in progress'
        else 'waiting'
        end
      end

      # met/late once the pull request is merged or its checks are green,
      # judged by when that happened against the due date; otherwise breached
      # once the due date has passed, ci failing while checks are red inside
      # the window, and in progress while checks are pending or unobserved.
      def pr_sla_word(due_at)
        return (green_at <= due_at ? 'met' : 'late') if green_at
        return 'breached' if now > due_at
        return 'ci failing' if record[:pr_checks] == 'failure'

        'in progress'
      end
    end

    attr_reader :repo, :now

    # `2m 30s` under an hour, `3h 12m` under a day, `2d 4h` from a day up.
    def self.duration(seconds)
      seconds = seconds.round
      return "#{seconds}s" if seconds < 60

      minutes, secs = seconds.divmod(60)
      return "#{minutes}m #{secs}s" if minutes < 60

      hours, minutes = minutes.divmod(60)
      return "#{hours}h #{minutes}m" if hours < 24

      days, hours = hours.divmod(24)
      "#{days}d #{hours}h"
    end

    def self.time(value)
      value.nil? ? NONE : value.getutc.strftime(TIME_FORMAT)
    end

    def initialize(db, repo: nil, now: Time.now.utc)
      @db = db
      @repo = repo
      @now = now
    end

    def rendered_at
      self.class.time(now)
    end

    def rows
      @rows ||= sorted(records).map { |record| Row.new(record, now: now) }
    end

    def summary
      @summary ||= Summary.new(
        findings: rows.size,
        fixed_inside_sla: rows.count { |row| row.sla == 'met' },
        breached: rows.count(&:breached?),
        median_time_to_green: median_time_to_green
      )
    end

    private

    def median_time_to_green
      seconds = rows.filter_map(&:seconds_to_green)
      return NOT_YET if seconds.empty?

      self.class.duration(median(seconds))
    end

    def median(values)
      sorted = values.sort
      mid = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def records
      @db[:findings]
        .left_join(:sessions, finding_id: :id)
        .select_all(:findings)
        .select_append(Sequel[:sessions][:id].as(:session_row_id), *SESSION_COLUMNS)
        .all
    end

    def sorted(records)
      records.sort_by do |record|
        [SEVERITY_ORDER.index(record[:severity]) || SEVERITY_ORDER.size, record[:due_at].to_i]
      end
    end
  end
end
