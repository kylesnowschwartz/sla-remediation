# frozen_string_literal: true

require 'json'
require 'json_schemer'
require 'logger'
require 'sequel'

require_relative 'devin_client/session'
require_relative 'remediation_prompt'
require_relative 'repair_prompt'

module SLA
  # Watches the Devin sessions the dispatcher started. Each round fetches every
  # open session, records what Devin reports on its sessions row, validates the
  # structured output against the schema the session was given, and hands the
  # finding to the notifier the first time a pull request appears.
  #
  # A row is open while its outcome is empty. It closes as "reported" once the
  # session has stopped with a report or a pull request, or as "stalled" once it
  # has stopped with neither; closed rows are never fetched again from Devin.
  #
  # A row with a pull request keeps being polled on GitHub for its checks after
  # it closes, until the checks are green or the pull request is merged or
  # closed. Without a GitHub client the pull request is never looked at and
  # the checks columns stay empty.
  #
  # When the checks are red on a commit no repair has been asked for, the
  # failed check runs are sent to the session that opened the pull request
  # (a message, not a new session), at most MAX_CI_REPAIRS times per session.
  # A session still working is left alone until it stops; the red commit is
  # sent then.
  class Tracker
    REPORTED = 'reported'
    STALLED = 'stalled'
    MERGED = 'merged'
    MAX_CI_REPAIRS = 2
    UNRESOLVED_CHECKS = %w[pending failure none].freeze
    PR_URL_PATTERN = %r{github\.com/(?<repo>[^/]+/[^/]+)/pull/(?<number>\d+)}
    EMPTY_SUMMARY = { polled: 0, reported: 0, stalled: 0, notified: 0, errors: 0 }.freeze

    def initialize(db:, devin:, notifier:, github: nil, schema: RemediationPrompt.schema, log: Logger.new($stdout))
      @db = db
      @devin = devin
      @notifier = notifier
      @github = github
      @schemer = JSONSchemer.schema(schema)
      @log = log
    end

    # Polls the pull request checks of every closed session still being
    # watched, then polls every open session (whose pull request is checked as
    # part of the poll). Returns {polled:, reported:, stalled:, notified:, errors:}.
    def poll_once
      summary = EMPTY_SUMMARY.dup
      watched_pr_sessions.each { |row| check_pr(row, summary) } if @github
      open_sessions.each { |row| poll_one(row, summary) }
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

    def poll_one(row, summary)
      summary[:polled] += 1
      poll(row, summary)
    rescue StandardError => e
      summary[:errors] += 1
      log_session_error(row, e)
    end

    def poll(row, summary)
      session = @devin.session(row[:devin_session_id])
      row = record(row, session)
      row = check_pr(row, summary) if row[:pr_url] && @github
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
      return unless session.stopped?

      if session.reported?
        sessions.where(id: row[:id]).update(outcome: REPORTED, finished_at: session.updated_at)
        summary[:reported] += 1
      else
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

    # Fetches the pull request's state, merge time and checks and writes them
    # onto the row, then asks the session to repair red checks, returning the
    # row as updated. A failure here is logged and counted but leaves the row
    # (and the rest of the poll) alone: the checks are written before the
    # repair is attempted, and the repair is recorded only once the message
    # has been delivered, so a failed delivery is retried next round. Logs
    # (without a new issue comment) when checks turn red.
    def check_pr(row, summary)
      status = pull_request_status(row)
      log_checks_failing(row, status)
      updated = write(row, pr_changes(row, status))
      write(updated, repair_changes(row, status))
    rescue StandardError => e
      summary[:errors] += 1
      log_session_error(row, e)
      row
    end

    def write(row, changes)
      sessions.where(id: row[:id]).update(changes) unless changes.empty?
      row.merge(changes)
    end

    def pull_request_status(row)
      @github.pull_request_status(*pull_request_ref(row))
    end

    def pull_request_ref(row)
      match = row[:pr_url].match(PR_URL_PATTERN)
      raise Error, "pull request URL #{row[:pr_url]} is not a GitHub pull request" unless match

      [match[:repo], match[:number].to_i]
    end

    # The check state and its time change together, and only when the state
    # changes; the time is when the checks completed, or when they were seen
    # while still pending or absent. The merge time is written once.
    def pr_changes(row, status)
      changes = { pr_state: status.merged ? MERGED : status.state, pr_head_sha: status.head_sha }
      changes.merge!(checks_changes(status)) if status.checks != row[:pr_checks]
      changes.merge!(merge_changes(status)) if status.merged && row[:pr_merged_at].nil?
      changes.reject { |column, value| row[column] == value }
    end

    def checks_changes(status)
      { pr_checks: status.checks, pr_checks_at: status.checks_at || Time.now.utc }
    end

    def merge_changes(status)
      { pr_merged_at: status.merged_at || Time.now.utc }
    end

    def log_checks_failing(row, status)
      return unless status.checks == 'failure' && row[:pr_checks] != 'failure'

      @log.info("tracker issue ##{issue_number(row)}: pull request #{row[:pr_url]} checks are red")
    end

    # Sends the failed check runs to the session once per red head commit of
    # an open pull request, once the session has stopped working, until the
    # session has been asked MAX_CI_REPAIRS times; after that the row stays
    # red for a human.
    def repair_changes(row, status)
      return {} unless unrepaired_red?(row, status)
      return log_repairs_exhausted(row, status) if row[:ci_repairs] >= MAX_CI_REPAIRS
      return log_repair_deferred(row, status) if session_working?(row)

      failures = @github.failed_check_runs(status)
      @devin.send_message(row[:devin_session_id], repair_message(row, status, failures))
      log_repair_sent(row, status, failures)
      { ci_repair_sha: status.head_sha, ci_repairs: row[:ci_repairs] + 1 }
    end

    def unrepaired_red?(row, status)
      status.state == 'open' && status.checks == 'failure' && row[:ci_repair_sha] != status.head_sha
    end

    # Whether the session is still running and has not stopped for input; the
    # row holds what Devin reported on this poll (or the last, for a closed row).
    def session_working?(row)
      row[:status] == 'running' && !DevinClient::Session::STOPPED_DETAILS.include?(row[:status_detail])
    end

    def repair_message(row, status, failures)
      RepairPrompt.render(pr_url: row[:pr_url], branch: status.head_branch, sha: status.head_sha, failures: failures)
    end

    def log_repair_sent(row, status, failures)
      @log.info("tracker issue ##{issue_number(row)}: asked session #{row[:devin_session_id]} to repair " \
                "#{failures.size} failed check run(s) at #{status.head_sha} " \
                "(repair #{row[:ci_repairs] + 1} of #{MAX_CI_REPAIRS})")
    end

    # Logs once per red commit, the first round it is seen red.
    def log_repair_deferred(row, status)
      return {} if red_before?(row, status)

      @log.info("tracker issue ##{issue_number(row)}: pull request #{row[:pr_url]} checks are red at " \
                "#{status.head_sha} while session #{row[:devin_session_id]} is still working; " \
                'the repair waits until it stops')
      {}
    end

    # Warns once per red commit, the first round it is seen red.
    def log_repairs_exhausted(row, status)
      return {} if red_before?(row, status)

      @log.warn("tracker issue ##{issue_number(row)}: pull request #{row[:pr_url]} checks are red at " \
                "#{status.head_sha} after #{MAX_CI_REPAIRS} repairs; leaving it for a human")
      {}
    end

    # Whether the row already had this commit's checks recorded as red before
    # this round's write.
    def red_before?(row, status)
      row[:pr_checks] == 'failure' && row[:pr_head_sha] == status.head_sha
    end

    def log_session_error(row, error)
      @log.error("tracker session #{row[:devin_session_id]}: #{error.class}: #{error.message}")
    end

    def open_sessions
      sessions.where(outcome: nil).exclude(devin_session_id: nil).order(:id).all
    end

    # Closed sessions whose pull request is neither merged nor closed and
    # whose checks are not yet green: unobserved, pending, red, or absent (a
    # fresh push has no check runs until its workflows start).
    def watched_pr_sessions
      sessions.exclude(outcome: nil)
              .exclude(pr_url: nil)
              .where(pr_merged_at: nil)
              .exclude(pr_state: 'closed')
              .where(Sequel[pr_checks: nil] | Sequel[pr_checks: UNRESOLVED_CHECKS])
              .order(:id).all
    end

    def findings
      @db[:findings]
    end

    def sessions
      @db[:sessions]
    end
  end
end
