# frozen_string_literal: true

require 'json'
require 'json_schemer'
require 'logger'
require 'sequel'

require_relative 'remediation_prompt'

module SLA
  # Watches the Devin sessions the dispatcher started. Each round fetches every
  # open session, records what Devin reports on its sessions row, validates the
  # structured output against the schema the session was given, and hands the
  # finding to the notifier the first time a pull request appears.
  #
  # A row is open while its outcome is empty. It closes as "settled" once the
  # session has stopped with a report or a pull request, or as "stalled" once it
  # has stopped with neither; closed rows are never fetched again.
  class Tracker
    SETTLED = 'settled'
    STALLED = 'stalled'
    EMPTY_SUMMARY = { polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }.freeze

    def initialize(db:, devin:, notifier:, schema: RemediationPrompt.schema, log: Logger.new($stdout))
      @db = db
      @devin = devin
      @notifier = notifier
      @schemer = JSONSchemer.schema(schema)
      @log = log
    end

    # Polls every open session once. Returns {polled:, settled:, stalled:, notified:, errors:}.
    def poll_once
      summary = EMPTY_SUMMARY.dup
      open_sessions.each do |row|
        summary[:polled] += 1
        poll(row, summary)
      rescue StandardError => e
        summary[:errors] += 1
        @log.error("tracker session #{row[:devin_session_id]}: #{e.class}: #{e.message}")
      end
      summary
    end

    # Polls forever, sleeping `interval` seconds between rounds and yielding
    # each round's summary.
    def run(interval: 15)
      loop do
        summary = poll_once
        yield summary if block_given?
        sleep interval
      end
    end

    private

    def poll(row, summary)
      session = @devin.session(row[:devin_session_id])
      row = record(row, session)
      notify(row, summary) if row[:pr_url] && row[:pr_notified_at].nil?
      close(row, session, summary)
    end

    # Writes what the session shows onto the row and returns the row as updated.
    def record(row, session)
      changes = observed(session).merge(report(row, session))
      log_status_change(row, session)
      sessions.where(id: row[:id]).update(changes)
      row.merge(changes)
    end

    def observed(session)
      pull = session.pull_requests.first
      { status: session.status, status_detail: session.status_detail, acus_consumed: session.acus_consumed,
        last_polled_at: Time.now.utc, pr_url: pull&.pr_url, pr_state: pull&.pr_state }.compact
    end

    def log_status_change(row, session)
      return if row.values_at(:status, :status_detail) == [session.status, session.status_detail]

      @log.info("tracker issue ##{issue_number(row)}: session #{session.session_id} is now " \
                "#{session.status}/#{session.status_detail}")
    end

    # The structured output as JSON text, under structured_output when it matches
    # the schema and under structured_output_invalid when it does not.
    def report(row, session)
      output = session.structured_output
      return {} if output.nil? || row[:structured_output]

      problem = @schemer.validate(output).first
      return { structured_output: JSON.generate(output) } if problem.nil?

      @log.warn("tracker issue ##{issue_number(row)}: structured output does not match the schema: " \
                "#{problem['error']}")
      { structured_output_invalid: JSON.generate(output) }
    end

    # Writes pr_notified_at before posting the comment and clears it again if
    # the post fails, so the row is retried next round.
    def notify(row, summary)
      finding = findings.first(id: row[:finding_id])
      @db.transaction { sessions.where(id: row[:id]).update(pr_notified_at: Time.now.utc) }
      post_comment(finding, row)
      summary[:notified] += 1
    end

    def post_comment(finding, row)
      @notifier.pr_opened(finding, row)
    rescue StandardError => e
      sessions.where(id: row[:id]).update(pr_notified_at: nil)
      @log.error("tracker issue ##{finding[:issue_number]}: posting the pull request comment failed: " \
                 "#{e.class}: #{e.message}")
      raise
    end

    def close(row, session, summary)
      if session.settled?
        sessions.where(id: row[:id]).update(outcome: SETTLED, finished_at: session.updated_at)
        summary[:settled] += 1
      elsif session.stalled?
        sessions.where(id: row[:id]).update(outcome: STALLED)
        summary[:stalled] += 1
        warn_stalled(row, session)
      end
    end

    def warn_stalled(row, session)
      @log.warn("tracker issue ##{issue_number(row)}: session #{session.session_id} stopped " \
                "(#{session.status}/#{session.status_detail}) without a report or a pull request")
    end

    def issue_number(row)
      findings.where(id: row[:finding_id]).get(:issue_number)
    end

    def open_sessions
      sessions.where(outcome: nil).exclude(devin_session_id: nil).order(:id).all
    end

    def findings
      @db[:findings]
    end

    def sessions
      @db[:sessions]
    end
  end
end
