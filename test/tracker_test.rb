# frozen_string_literal: true

require 'stringio'

require_relative 'test_helper'

module SLA
  class TrackerTest < Minitest::Test
    ORG_ID = 'org-test'
    SESSIONS_URL = "https://api.devin.ai/v3/organizations/#{ORG_ID}/sessions".freeze
    FIXTURES = File.expand_path('fixtures/devin', __dir__)
    JSON_HEADER = { 'Content-Type' => 'application/json' }.freeze
    SETTLED_ID = '812ce7c3f89f4e88bce68dc03c9dd462'
    WAITING_ID = '7cde046172a044b18c55ceeabe09e028'
    SUSPENDED_ID = '18fc67a110a9424ebf9561ebfba3757b'
    WORKING_ID = 'aaaa0000000000000000000000000001'
    STALLED_ID = 'aaaa0000000000000000000000000002'
    CHANGING_ID = 'aaaa0000000000000000000000000003'
    PR_URL = 'https://github.com/kylesnowschwartz/superset/pull/9'
    GREEN_RUN = { status: 'completed', conclusion: 'success', completed_at: '2026-09-02T08:44:00Z' }.freeze
    RED_RUN = { status: 'completed', conclusion: 'failure', completed_at: '2026-09-02T08:50:00Z' }.freeze
    PENDING_RUN = { status: 'in_progress', conclusion: nil, completed_at: nil }.freeze

    # Records every pr_opened call.
    class SpyNotifier
      attr_reader :calls

      def initialize
        @calls = []
      end

      def pr_opened(finding_row, session_row)
        @calls << [finding_row, session_row]
      end
    end

    def setup
      DB[:sessions].delete
      DB[:findings].delete
      @log_io = StringIO.new
      @notifier = SpyNotifier.new
      @github = GitHubClient.new(token: 'test-token')
      @tracker = Tracker.new(db: DB, devin: DevinClient.new(api_key: 'test-key', org_id: ORG_ID),
                             notifier: @notifier, github: @github, log: Logger.new(@log_io))
    end

    def stub_pr_status(repo, number, sha:, state: 'open', merged: false, merged_at: nil, check_runs: [])
      stub_request(:get, "https://api.github.com/repos/#{repo}/pulls/#{number}")
        .to_return(status: 200, body: { number: number, state: state, merged: merged, merged_at: merged_at,
                                        mergeable: true, head: { sha: sha } }.to_json, headers: JSON_HEADER)
      stub_request(:get, "https://api.github.com/repos/#{repo}/commits/#{sha}/check-runs")
        .with(query: { per_page: '100' })
        .to_return(status: 200, body: { check_runs: check_runs }.to_json, headers: JSON_HEADER)
    end

    # A closed (settled) row whose pull request is already known, as the watch
    # loop finds it.
    def record_settled_pr_session(issue_number, **columns)
      row_id = record_session(issue_number, SETTLED_ID)
      DB[:sessions].where(id: row_id).update({ pr_url: PR_URL, pr_state: 'open', pr_notified_at: Time.now.utc,
                                               outcome: 'settled' }.merge(columns))
      row_id
    end

    def test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once
      row_id = record_session(8, SETTLED_ID)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [GREEN_RUN])

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 1, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_equal 'running', row[:status]
      assert_equal 'waiting_for_user', row[:status_detail]
      assert_in_delta 0.0, row[:acus_consumed]
      assert_in_delta Time.now.utc, row[:last_polled_at], 5
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/9', row[:pr_url]
      assert_equal 'open', row[:pr_state]
      assert_equal 'settled', row[:outcome]
      assert_equal Time.at(1_788_342_608).utc, row[:finished_at]
      assert_in_delta Time.now.utc, row[:pr_notified_at], 5
      assert_equal 'success', row[:pr_checks]
      assert_equal Time.utc(2026, 9, 2, 8, 44, 0), row[:pr_checks_at]
      assert_nil row[:pr_merged_at]
      assert_nil row[:structured_output_invalid]
      output = JSON.parse(row[:structured_output])

      assert_equal 'urllib3', output['package']
      assert_equal %w[GHSA-qccp-gfcp-xxvc GHSA-pq67-6m6q-mj2v GHSA-gm62-xv2j-4w53 GHSA-48p4-8xcf-vxj5
                      GHSA-2xpw-w6gg-jr37 GHSA-38jv-5279-wg99], output['advisories_cleared']
      assert_equal 1, @notifier.calls.size
      finding_row, session_row = @notifier.calls.first

      assert_equal 8, finding_row[:issue_number]
      assert_equal SETTLED_ID, session_row[:devin_session_id]
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/9', session_row[:pr_url]
      refute_match(/WARN|ERROR/, @log_io.string)

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_requested :get, "#{SESSIONS_URL}/#{SETTLED_ID}", times: 1
      assert_requested :get, %r{api\.github\.com/repos/kylesnowschwartz/superset/pulls/9}, times: 1
      assert_equal 1, @notifier.calls.size
    end

    def test_pr_checks_at_is_unchanged_when_checks_are_still_success
      row_id = record_session(7, WORKING_ID)
      old_checks_at = Time.now.utc - 3600
      DB[:sessions].where(id: row_id).update(pr_url: PR_URL, pr_state: 'open', pr_checks: 'success',
                                             pr_checks_at: old_checks_at)
      stub_session(WORKING_ID, hand_written(WORKING_ID, status: 'running', status_detail: 'waiting_for_user',
                                                        pull_requests: [{ 'pr_url' => PR_URL,
                                                                          'pr_state' => 'open' }]))
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [GREEN_RUN])

      @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal 'success', row[:pr_checks]
      assert_equal old_checks_at.to_i, row[:pr_checks_at].to_i
    end

    def test_a_settled_row_with_pending_checks_is_watched_until_they_pass
      row_id = record_settled_pr_session(8, pr_checks: 'pending', pr_checks_at: Time.now.utc - 60)
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [PENDING_RUN])

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_equal 'pending', DB[:sessions].first(id: row_id)[:pr_checks]

      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [GREEN_RUN])
      @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal 'success', row[:pr_checks]
      assert_equal Time.utc(2026, 9, 2, 8, 44, 0), row[:pr_checks_at]
      assert_equal 'open', row[:pr_state]
      assert_nil row[:pr_merged_at]

      @tracker.poll_once

      assert_requested :get, %r{api\.github\.com/repos/kylesnowschwartz/superset/pulls/9}, times: 2
      assert_not_requested :get, /api\.devin\.ai/
      assert_empty @notifier.calls
    end

    def test_a_settled_row_without_check_runs_yet_is_watched_until_they_appear
      row_id = record_settled_pr_session(8)
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [])

      @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal 'none', row[:pr_checks]
      assert_in_delta Time.now.utc, row[:pr_checks_at], 5

      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [RED_RUN])
      @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal 'failure', row[:pr_checks]
      assert_equal Time.utc(2026, 9, 2, 8, 50, 0), row[:pr_checks_at]
      assert_match(/INFO.*issue #8: pull request #{PR_URL} checks are red/, @log_io.string)
    end

    def test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched
      row_id = record_settled_pr_session(8, pr_checks: 'failure', pr_checks_at: Time.now.utc - 60)
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', state: 'closed', merged: true,
                                                     merged_at: '2026-09-02T09:00:00Z', check_runs: [RED_RUN])

      @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal 'merged', row[:pr_state]
      assert_equal Time.utc(2026, 9, 2, 9, 0, 0), row[:pr_merged_at]
      assert_equal 'failure', row[:pr_checks]

      @tracker.poll_once

      assert_requested :get, %r{api\.github\.com/repos/kylesnowschwartz/superset/pulls/9}, times: 1
    end

    def test_a_pull_request_closed_without_merging_stops_being_watched
      row_id = record_settled_pr_session(8, pr_checks: 'pending', pr_checks_at: Time.now.utc - 60)
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', state: 'closed', check_runs: [PENDING_RUN])

      @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal 'closed', row[:pr_state]
      assert_nil row[:pr_merged_at]

      @tracker.poll_once

      assert_requested :get, %r{api\.github\.com/repos/kylesnowschwartz/superset/pulls/9}, times: 1
    end

    def test_a_github_error_while_checking_the_pull_request_is_counted_and_leaves_the_row_alone
      row_id = record_settled_pr_session(8, pr_checks: 'pending', pr_checks_at: Time.now.utc - 60)
      stub_request(:get, 'https://api.github.com/repos/kylesnowschwartz/superset/pulls/9')
        .to_return(status: 502, body: '{"message":"bad gateway"}', headers: JSON_HEADER)

      summary = @tracker.poll_once

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 1 }, summary)
      assert_equal 'pending', DB[:sessions].first(id: row_id)[:pr_checks]
      assert_match(/ERROR.*session #{SETTLED_ID}: SLA::GitHubAPIError/, @log_io.string)
    end

    def test_a_github_error_during_an_open_poll_still_notifies_and_closes_the_session
      row_id = record_session(8, SETTLED_ID)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))
      stub_request(:get, 'https://api.github.com/repos/kylesnowschwartz/superset/pulls/9')
        .to_return(status: 502, body: '{"message":"bad gateway"}', headers: JSON_HEADER)

      summary = @tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 1, errors: 1 }, summary)
      assert_equal 'settled', row[:outcome]
      assert_nil row[:pr_checks]
      assert_equal 1, @notifier.calls.size
    end

    def test_a_pull_request_url_off_github_is_an_error_not_a_crash
      record_settled_pr_session(8, pr_url: 'https://gitlab.com/x/y/-/merge_requests/1')

      summary = @tracker.poll_once

      assert_equal 1, summary[:errors]
      assert_match(%r{ERROR.*SLA::Error: pull request URL https://gitlab.com/x/y/-/merge_requests/1 is not a GitHub},
                   @log_io.string)
      assert_not_requested :get, /api\.github\.com/
    end

    def test_without_a_github_client_pull_requests_are_never_looked_at
      record_settled_pr_session(8, pr_checks: 'pending', pr_checks_at: Time.now.utc - 60)
      row_id = record_session(2, SUSPENDED_ID)
      stub_session(SUSPENDED_ID, fixture('get_session_suspended_with_pr.json'))
      tracker = Tracker.new(db: DB, devin: DevinClient.new(api_key: 'test-key', org_id: ORG_ID),
                            notifier: @notifier, log: Logger.new(@log_io))

      summary = tracker.poll_once
      row = DB[:sessions].first(id: row_id)

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 1, errors: 0 }, summary)
      assert_equal 'settled', row[:outcome]
      assert_nil row[:pr_checks]
      assert_not_requested :get, /api\.github\.com/
    end

    def test_output_of_another_shape_is_kept_as_invalid_with_a_warning
      row_id = record_session(4, WAITING_ID)
      stub_session(WAITING_ID, fixture('get_session_waiting_for_user.json'))

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 0, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_equal 'settled', row[:outcome]
      assert_equal Time.at(1_788_336_350).utc, row[:finished_at]
      assert_nil row[:structured_output]
      assert_nil row[:pr_url]
      assert_nil row[:pr_notified_at]
      invalid = JSON.parse(row[:structured_output_invalid])

      assert_equal 'master', invalid['default_branch']
      assert_equal({ 'flask' => '2.3.3', 'urllib3' => '2.4.0', 'paramiko' => '3.5.1' }, invalid['pins'])
      assert_match(/WARN.*issue #4: structured output does not match the schema: object at root is missing required/,
                   @log_io.string)
      assert_empty @notifier.calls
    end

    def test_suspended_session_with_pull_request_is_settled_and_notified_once
      row_id = record_session(2, SUSPENDED_ID)
      stub_session(SUSPENDED_ID, fixture('get_session_suspended_with_pr.json'))
      stub_pr_status('kylesnowschwartz/superset', 2, sha: 'd4e5f6', check_runs: [GREEN_RUN])

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 1, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_equal 'suspended', row[:status]
      assert_equal 'inactivity', row[:status_detail]
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/2', row[:pr_url]
      assert_equal 'open', row[:pr_state]
      assert_equal 'settled', row[:outcome]
      assert_equal 'success', row[:pr_checks]
      assert_nil row[:structured_output]
      assert_nil row[:structured_output_invalid]
      assert_equal 1, @notifier.calls.size
      refute_match(/WARN|ERROR/, @log_io.string)
    end

    def test_working_session_stays_open
      row_id = record_session(5, WORKING_ID)
      stub_session(WORKING_ID, hand_written(WORKING_ID, status: 'running', status_detail: 'working'))

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_nil row[:outcome]
      assert_equal 'running', row[:status]
      assert_equal 'working', row[:status_detail]
      assert_nil row[:pr_url]
      assert_nil row[:finished_at]
      assert_empty @notifier.calls
      refute_match(/WARN|ERROR/, @log_io.string)

      assert_equal({ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_requested :get, "#{SESSIONS_URL}/#{WORKING_ID}", times: 2
    end

    def test_suspended_session_without_report_or_pull_request_is_stalled
      row_id = record_session(6, STALLED_ID)
      stub_session(STALLED_ID, hand_written(STALLED_ID, status: 'suspended', status_detail: 'inactivity'))

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 0, stalled: 1, notified: 0, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_equal 'stalled', row[:outcome]
      assert_nil row[:finished_at]
      assert_match(%r{WARN.*issue #6: session #{STALLED_ID} stopped \(suspended/inactivity\)}, @log_io.string)
      assert_empty @notifier.calls

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_requested :get, "#{SESSIONS_URL}/#{STALLED_ID}", times: 1
    end

    def test_a_status_change_is_logged_once
      row_id = record_session(7, CHANGING_ID)
      stub_session(CHANGING_ID, hand_written(CHANGING_ID, status: 'running', status_detail: 'working'))

      @tracker.poll_once
      @tracker.poll_once

      assert_equal 1, @log_io.string.scan(%r{INFO.*issue #7: session #{CHANGING_ID} is now running/working}).size

      stub_session(CHANGING_ID, hand_written(CHANGING_ID, status: 'running', status_detail: 'waiting_for_approval'))
      @tracker.poll_once
      @tracker.poll_once

      assert_equal 1, @log_io.string.scan(%r{issue #7: session #{CHANGING_ID} is now running/waiting_for_approval}).size
      assert_equal 2, @log_io.string.scan('INFO').size
      row = DB[:sessions].first(id: row_id)

      assert_nil row[:outcome]
      assert_equal 'waiting_for_approval', row[:status_detail]
      assert_requested :get, "#{SESSIONS_URL}/#{CHANGING_ID}", times: 4
      assert_empty @notifier.calls
    end

    def test_an_error_for_one_session_does_not_stop_the_others
      failing_id = record_session(5, WORKING_ID)
      settled_id = record_session(8, SETTLED_ID)
      stub_request(:get, "#{SESSIONS_URL}/#{WORKING_ID}").to_return(status: 503, body: '{"detail":"unavailable"}',
                                                                    headers: JSON_HEADER)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [GREEN_RUN])

      summary = @tracker.poll_once

      assert_equal({ polled: 2, settled: 1, stalled: 0, notified: 1, errors: 1 }, summary)
      assert_equal 'settled', DB[:sessions].first(id: settled_id)[:outcome]
      failing = DB[:sessions].first(id: failing_id)

      assert_nil failing[:outcome]
      assert_equal 'new', failing[:status]
      assert_match(/ERROR.*session #{WORKING_ID}: SLA::DevinAPIError: Devin API returned 503/, @log_io.string)
      assert_equal 1, @notifier.calls.size
    end

    def test_a_failed_notification_clears_the_timestamp_and_leaves_the_row_open
      row_id = record_session(8, SETTLED_ID)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))
      stub_pr_status('kylesnowschwartz/superset', 9, sha: 'a1b2c3', check_runs: [GREEN_RUN])
      seen = []
      failing = Object.new
      failing.define_singleton_method(:pr_opened) do |_finding, session_row|
        seen << DB[:sessions].first(id: session_row[:id])[:pr_notified_at]
        raise GitHubAPIError.new(status: 502, body: 'bad gateway')
      end
      tracker = Tracker.new(db: DB, devin: DevinClient.new(api_key: 'test-key', org_id: ORG_ID), notifier: failing,
                            github: @github, log: Logger.new(@log_io))

      summary = tracker.poll_once

      assert_equal({ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 1 }, summary)
      assert_in_delta Time.now.utc, seen.fetch(0), 5
      row = DB[:sessions].first(id: row_id)

      assert_nil row[:outcome]
      assert_nil row[:pr_notified_at]
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/9', row[:pr_url]
      assert_match(/ERROR.*issue #8: posting the pull request comment failed: SLA::GitHubAPIError/, @log_io.string)
      assert_match(/ERROR.*session #{SETTLED_ID}: SLA::GitHubAPIError/, @log_io.string)
    end

    def test_rows_without_a_devin_session_id_are_skipped
      finding_id = record_finding(9)
      DB[:sessions].insert(finding_id: finding_id, status: 'dispatching', last_polled_at: Time.now.utc)

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_not_requested :get, /api\.devin\.ai/
    end

    def test_run_polls_and_yields_each_summary_between_sleeps
      record_session(5, WORKING_ID)
      stub_session(WORKING_ID, hand_written(WORKING_ID, status: 'running', status_detail: 'working'))
      summaries = []

      thread = Thread.new { @tracker.run(interval: 60) { |summary| summaries << summary } }
      Thread.pass until summaries.size == 1
      Thread.pass until thread.status == 'sleep'
      thread.kill
      thread.join

      assert_equal [{ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 0 }], summaries
      assert_requested :get, "#{SESSIONS_URL}/#{WORKING_ID}", times: 1
    end

    private

    def stub_session(session_id, body)
      stub_request(:get, "#{SESSIONS_URL}/#{session_id}").to_return(status: 200, body: body, headers: JSON_HEADER)
    end

    def hand_written(session_id, status:, status_detail:, pull_requests: [])
      JSON.generate(
        'session_id' => session_id, 'url' => "https://app.devin.ai/sessions/#{session_id}", 'status' => status,
        'title' => '[SLA high] urllib3 2.4.0 → 2.7.0', 'tags' => ['sla-remediation'], 'created_at' => 1_788_342_462,
        'updated_at' => 1_788_342_500, 'acus_consumed' => 0.0, 'pull_requests' => pull_requests,
        'structured_output' => nil, 'status_detail' => status_detail
      )
    end

    def record_session(issue_number, session_id)
      DB[:sessions].insert(finding_id: record_finding(issue_number), devin_session_id: session_id, status: 'new',
                           started_at: Time.now.utc, last_polled_at: Time.now.utc)
    end

    def record_finding(issue_number)
      DB[:findings].insert(issue_number: issue_number, issue_title: '[SLA high] urllib3 2.4.0 → 2.7.0',
                           issue_url: "https://github.com/kylesnowschwartz/superset/issues/#{issue_number}",
                           package: 'urllib3', pinned: '2.4.0', fix_version: '2.7.0', severity: 'high',
                           source: 'pip-audit', advisories: '["GHSA-qccp-gfcp-xxvc"]',
                           opened_at: Time.utc(2026, 9, 2, 8, 25, 30), due_at: Time.utc(2026, 9, 4, 8, 25, 30),
                           created_at: Time.now.utc)
    end

    def fixture(name)
      File.read(File.join(FIXTURES, name))
    end
  end
end
