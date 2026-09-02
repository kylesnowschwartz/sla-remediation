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
    APPROVAL_ID = 'aaaa0000000000000000000000000003'

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
      @tracker = Tracker.new(db: DB, devin: DevinClient.new(api_key: 'test-key', org_id: ORG_ID),
                             notifier: @notifier, log: Logger.new(@log_io))
    end

    def test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once
      row_id = record_session(8, SETTLED_ID)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 1, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_equal 'running', row[:status]
      assert_equal 'waiting_for_user', row[:status_detail]
      assert_in_delta 0.0, row[:acus_consumed]
      assert_equal 1, row[:poll_count]
      assert_in_delta Time.now.utc, row[:last_polled_at], 5
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/9', row[:pr_url]
      assert_equal 'open', row[:pr_state]
      assert_equal 'settled', row[:outcome]
      assert_equal Time.at(1_788_342_608).utc, row[:finished_at]
      assert_in_delta Time.now.utc, row[:pr_notified_at], 5
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
      assert_empty @log_io.string

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_requested :get, "#{SESSIONS_URL}/#{SETTLED_ID}", times: 1
      assert_equal 1, @notifier.calls.size
      assert_equal 1, DB[:sessions].first(id: row_id)[:poll_count]
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

      summary = @tracker.poll_once

      assert_equal({ polled: 1, settled: 1, stalled: 0, notified: 1, errors: 0 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_equal 'suspended', row[:status]
      assert_equal 'inactivity', row[:status_detail]
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/2', row[:pr_url]
      assert_equal 'open', row[:pr_state]
      assert_equal 'settled', row[:outcome]
      assert_nil row[:structured_output]
      assert_nil row[:structured_output_invalid]
      assert_equal 1, @notifier.calls.size
      assert_empty @log_io.string
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
      assert_equal 1, row[:poll_count]
      assert_nil row[:pr_url]
      assert_nil row[:finished_at]
      assert_empty @notifier.calls
      assert_empty @log_io.string

      @tracker.poll_once

      assert_equal 2, DB[:sessions].first(id: row_id)[:poll_count]
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

    def test_waiting_for_approval_stays_open_and_warns_once
      row_id = record_session(7, APPROVAL_ID)
      stub_session(APPROVAL_ID, hand_written(APPROVAL_ID, status: 'running', status_detail: 'waiting_for_approval'))

      assert_equal({ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      row = DB[:sessions].first(id: row_id)

      assert_nil row[:outcome]
      assert_equal 'waiting_for_approval', row[:status_detail]
      assert_equal 1, @log_io.string.scan(/WARN.*issue #7: session #{APPROVAL_ID} is waiting for approval/).size

      assert_equal({ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_equal 2, DB[:sessions].first(id: row_id)[:poll_count]
      assert_equal 1, @log_io.string.scan('waiting for approval').size
      assert_empty @notifier.calls
    end

    def test_an_error_for_one_session_does_not_stop_the_others
      failing_id = record_session(5, WORKING_ID)
      settled_id = record_session(8, SETTLED_ID)
      stub_request(:get, "#{SESSIONS_URL}/#{WORKING_ID}").to_return(status: 503, body: '{"detail":"unavailable"}',
                                                                    headers: JSON_HEADER)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))

      summary = @tracker.poll_once

      assert_equal({ polled: 2, settled: 1, stalled: 0, notified: 1, errors: 1 }, summary)
      assert_equal 'settled', DB[:sessions].first(id: settled_id)[:outcome]
      failing = DB[:sessions].first(id: failing_id)

      assert_nil failing[:outcome]
      assert_equal 0, failing[:poll_count]
      assert_match(/ERROR.*session #{WORKING_ID}: SLA::DevinAPIError: Devin API returned 503/, @log_io.string)
      assert_equal 1, @notifier.calls.size
    end

    def test_a_failed_notification_leaves_the_row_open_and_unnotified
      row_id = record_session(8, SETTLED_ID)
      stub_session(SETTLED_ID, fixture('get_session_settled_with_pr_and_output.json'))
      failing = Object.new
      failing.define_singleton_method(:pr_opened) { |*| raise GitHubAPIError.new(status: 502, body: 'bad gateway') }
      tracker = Tracker.new(db: DB, devin: DevinClient.new(api_key: 'test-key', org_id: ORG_ID), notifier: failing,
                            log: Logger.new(@log_io))

      summary = tracker.poll_once

      assert_equal({ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 1 }, summary)
      row = DB[:sessions].first(id: row_id)

      assert_nil row[:outcome]
      assert_nil row[:pr_notified_at]
      assert_equal 'https://github.com/kylesnowschwartz/superset/pull/9', row[:pr_url]
      assert_equal 1, row[:poll_count]
    end

    def test_rows_without_a_devin_session_id_are_skipped
      finding_id = record_finding(9)
      DB[:sessions].insert(finding_id: finding_id, status: 'dispatching', last_polled_at: Time.now.utc)

      assert_equal({ polled: 0, settled: 0, stalled: 0, notified: 0, errors: 0 }, @tracker.poll_once)
      assert_not_requested :get, /api\.devin\.ai/
    end

    def test_run_polls_until_stopped_and_yields_each_summary
      record_session(5, WORKING_ID)
      stub_session(WORKING_ID, hand_written(WORKING_ID, status: 'running', status_detail: 'working'))
      stop = Queue.new
      summaries = []

      thread = Thread.new do
        @tracker.run(interval: 60, stop: stop) { |summary| summaries << summary }
      end
      Thread.pass until summaries.size == 1
      stop << :stop

      assert thread.join(5), 'run did not stop within 5 seconds'
      assert_equal [{ polled: 1, settled: 0, stalled: 0, notified: 0, errors: 0 }], summaries
      assert_requested :get, "#{SESSIONS_URL}/#{WORKING_ID}", times: 1
    end

    private

    def stub_session(session_id, body)
      stub_request(:get, "#{SESSIONS_URL}/#{session_id}").to_return(status: 200, body: body, headers: JSON_HEADER)
    end

    def hand_written(session_id, status:, status_detail:)
      JSON.generate(
        'session_id' => session_id, 'url' => "https://app.devin.ai/sessions/#{session_id}", 'status' => status,
        'title' => '[SLA high] urllib3 2.4.0 → 2.7.0', 'tags' => ['sla-remediation'], 'created_at' => 1_788_342_462,
        'updated_at' => 1_788_342_500, 'acus_consumed' => 0.0, 'pull_requests' => [], 'structured_output' => nil,
        'status_detail' => status_detail
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
