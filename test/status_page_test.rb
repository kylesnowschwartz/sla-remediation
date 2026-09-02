# frozen_string_literal: true

require_relative 'test_helper'

module SLA
  class StatusPageTest < Minitest::Test
    NOW = Time.utc(2026, 9, 3, 12, 0, 0)
    DUE = Time.utc(2026, 9, 4, 8, 25, 30)
    SESSION_ID = '812ce7c3f89f4e88bce68dc03c9dd462'

    def setup
      DB[:sessions].delete
      DB[:findings].delete
    end

    def test_met_when_the_pull_request_was_seen_before_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, devin_session_id: SESSION_ID, outcome: 'settled', pr_state: 'open',
                                 pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9',
                                 pr_notified_at: DUE - 3600)

      row = page.rows.fetch(0)

      assert_equal 'met', row.sla
      assert_equal 'sla-met', row.sla_class
      assert_equal '9', row.pr_number
      assert_equal 'open', row.pr_state
      assert_equal 'settled', row.devin
      assert_equal "https://app.devin.ai/sessions/#{SESSION_ID}", row.devin_url
    end

    def test_late_when_the_pull_request_was_seen_after_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE + 60, outcome: 'settled')

      assert_equal 'late', page(now: DUE + 120).rows.fetch(0).sla
    end

    def test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed
      finding_id = record_finding(1)
      record_session(finding_id, status: 'running', status_detail: 'working')

      row = page(now: DUE + 1).rows.fetch(0)

      assert_equal 'breached', row.sla
      assert_equal '1s ago', row.due_in
      assert_equal 'running/working', row.devin
    end

    def test_breached_takes_precedence_over_a_stalled_session_once_the_due_date_has_passed
      finding_id = record_finding(1)
      record_session(finding_id, status: 'suspended', status_detail: 'inactivity', outcome: 'stalled')

      assert_equal 'breached', page(now: DUE + 1).rows.fetch(0).sla
    end

    def test_stalled_when_the_session_stopped_without_a_pull_request_inside_the_window
      finding_id = record_finding(1)
      record_session(finding_id, status: 'suspended', status_detail: 'inactivity', outcome: 'stalled')

      row = page.rows.fetch(0)

      assert_equal 'stalled', row.sla
      assert_equal 'stalled', row.devin
    end

    def test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window
      finding_id = record_finding(1)
      record_session(finding_id, status: 'running', status_detail: 'working')

      row = page.rows.fetch(0)

      assert_equal 'in progress', row.sla
      assert_equal 'sla-in-progress', row.sla_class
      assert_equal 'running/working', row.devin
      assert_equal 'in 20h 25m', row.due_in
      assert_nil row.pr_url
      assert_equal '—', row.time_to_pr
    end

    def test_waiting_when_nothing_has_been_dispatched_inside_the_window
      record_finding(1)

      row = page.rows.fetch(0)

      assert_equal 'waiting', row.sla
      assert_equal 'not dispatched', row.devin
      assert_nil row.devin_url
      assert_equal 'not reported', row.acus
    end

    def test_a_reserved_session_row_without_a_devin_session_id_counts_as_in_progress_without_a_link
      finding_id = record_finding(1)
      DB[:sessions].insert(finding_id: finding_id, status: 'dispatching', last_polled_at: NOW)

      row = page.rows.fetch(0)

      assert_equal 'in progress', row.sla
      assert_equal 'dispatching', row.devin
      assert_nil row.devin_url
    end

    def test_rows_are_sorted_by_severity_then_by_due_date
      record_finding(1, severity: 'low', due_at: DUE)
      record_finding(2, severity: 'critical', due_at: DUE + 7200)
      record_finding(3, severity: 'high', due_at: DUE)
      record_finding(4, severity: 'unknown', due_at: DUE)
      record_finding(5, severity: 'critical', due_at: DUE)
      record_finding(6, severity: 'medium', due_at: DUE)

      assert_equal [5, 2, 3, 6, 1, 4], page.rows.map(&:issue_number)
    end

    def test_summary_counts_findings_open_pull_requests_and_the_two_sides_of_the_window
      record_session(record_finding(1, due_at: DUE), pr_url: 'https://github.com/x/y/pull/1', pr_state: 'open',
                                                     pr_notified_at: DUE - 60, outcome: 'settled')
      record_session(record_finding(2, due_at: DUE), pr_url: 'https://github.com/x/y/pull/2', pr_state: 'merged',
                                                     pr_notified_at: DUE + 60, outcome: 'settled')
      record_session(record_finding(3, due_at: NOW - 60), status: 'running', status_detail: 'working')
      record_session(record_finding(4, due_at: DUE), status: 'suspended', status_detail: 'inactivity',
                                                     outcome: 'stalled')
      record_finding(5, due_at: DUE)

      summary = page.summary

      assert_equal 5, summary.findings
      assert_equal 1, summary.pull_requests_open
      assert_equal 3, summary.inside_sla
      assert_equal 2, summary.breached
      assert_equal %w[breached met late stalled waiting], page.rows.map(&:sla)
    end

    def test_row_strings_are_formatted_for_the_template
      finding_id = record_finding(8, fix_version: nil)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: Time.utc(2026, 9, 2, 8, 44, 0), acus_consumed: 1.25)

      row = page.rows.fetch(0)

      assert_equal 8, row.issue_number
      assert_equal 'https://github.com/kylesnowschwartz/superset/issues/8', row.issue_url
      assert_equal '[SLA high] urllib3 2.4.0 → 2.7.0', row.issue_title
      assert_equal 'urllib3', row.package
      assert_equal '2.4.0 → no fix', row.versions
      assert_equal 'high', row.severity
      assert_equal '2026-09-02 08:25 UTC', row.filed
      assert_equal '2026-09-04 08:25 UTC', row.due
      assert_equal 'in 20h 25m', row.due_in
      assert_equal '18m 30s', row.time_to_pr
      assert_equal '1.25', row.acus
      assert_equal '2026-09-03 12:00 UTC', page.rendered_at
      assert_equal 'kylesnowschwartz/superset', page.repo
    end

    def test_fix_version_is_shown_when_present
      record_finding(1)

      assert_equal '2.4.0 → 2.7.0', page.rows.fetch(0).versions
    end

    def test_acus_are_not_reported_when_nil_or_zero
      record_session(record_finding(1), acus_consumed: nil)
      record_session(record_finding(2), acus_consumed: 0.0)

      assert_equal ['not reported', 'not reported'], page.rows.map(&:acus)
    end

    def test_a_pull_request_whose_comment_is_being_retried_is_judged_by_now
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/x/y/pull/1', pr_state: 'open', pr_notified_at: nil)

      assert_equal 'met', page.rows.fetch(0).sla
      assert_equal 'late', page(now: DUE + 1).rows.fetch(0).sla
      assert_equal '—', page.rows.fetch(0).time_to_pr
    end

    def test_duration_reads_in_seconds_minutes_hours_or_days
      assert_equal '45s', StatusPage.duration(45)
      assert_equal '2m 30s', StatusPage.duration(150)
      assert_equal '59m 59s', StatusPage.duration(3599)
      assert_equal '1h 0m', StatusPage.duration(3600)
      assert_equal '3h 12m', StatusPage.duration((3 * 3600) + (12 * 60) + 40)
      assert_equal '1d 0h', StatusPage.duration(86_400)
      assert_equal '2d 4h', StatusPage.duration((2 * 86_400) + (4 * 3600) + 59)
      assert_equal '2m 31s', StatusPage.duration(150.6)
    end

    private

    def page(now: NOW)
      StatusPage.new(DB, repo: 'kylesnowschwartz/superset', now: now)
    end

    def record_finding(issue_number, severity: 'high', due_at: DUE, fix_version: '2.7.0')
      DB[:findings].insert(issue_number: issue_number, issue_title: '[SLA high] urllib3 2.4.0 → 2.7.0',
                           issue_url: "https://github.com/kylesnowschwartz/superset/issues/#{issue_number}",
                           package: 'urllib3', pinned: '2.4.0', fix_version: fix_version, severity: severity,
                           source: 'pip-audit', advisories: '["GHSA-qccp-gfcp-xxvc"]',
                           opened_at: Time.utc(2026, 9, 2, 8, 25, 30), due_at: due_at,
                           created_at: Time.utc(2026, 9, 2, 8, 25, 30))
    end

    def record_session(finding_id, **columns)
      DB[:sessions].insert({ finding_id: finding_id, devin_session_id: "session-#{finding_id}", status: 'running',
                             status_detail: 'waiting_for_user', started_at: Time.utc(2026, 9, 2, 8, 25, 30),
                             last_polled_at: NOW }.merge(columns))
    end
  end
end
