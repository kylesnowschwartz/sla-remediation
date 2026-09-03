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

    def test_met_when_the_pull_request_merged_before_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, devin_session_id: SESSION_ID, outcome: 'settled', pr_state: 'merged',
                                 pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9',
                                 pr_notified_at: DUE - 3600, pr_merged_at: DUE - 1800)

      row = page.rows.fetch(0)

      assert_equal 'met', row.sla
      assert_equal 'sla-met', row.sla_class
      assert_equal '9', row.pr_number
      assert_equal 'merged', row.pr_state
      assert_equal 'settled', row.devin
      assert_equal "https://app.devin.ai/sessions/#{SESSION_ID}", row.devin_url
    end

    def test_met_when_the_pull_request_checks_went_green_before_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'success', pr_checks_at: DUE - 1800,
                                 outcome: 'settled')

      assert_equal 'met', page.rows.fetch(0).sla
    end

    def test_met_stays_met_when_evaluated_long_after_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'success', pr_checks_at: DUE - 1800,
                                 outcome: 'settled')

      assert_equal 'met', page(now: DUE + 86_400).rows.fetch(0).sla
    end

    def test_late_when_the_pull_request_merged_after_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'merged',
                                 pr_notified_at: DUE + 60, pr_merged_at: DUE + 90, outcome: 'settled')

      assert_equal 'late', page(now: DUE + 120).rows.fetch(0).sla
    end

    def test_in_progress_when_the_pull_requests_checks_are_pending
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'pending', pr_checks_at: NOW)

      row = page.rows.fetch(0)

      assert_equal 'in progress', row.sla
      assert_equal 'sla-in-progress', row.sla_class
    end

    def test_ci_failing_when_checks_are_red_inside_the_window
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'failure', pr_checks_at: NOW)

      row = page.rows.fetch(0)

      assert_equal 'ci failing', row.sla
      assert_equal 'sla-ci-failing', row.sla_class
      assert_equal '[CI FAILING]', row.sla_tag
      assert_equal 0, row.ci_repairs
      refute_predicate row, :ci_repairs?
    end

    def test_repairing_when_checks_are_red_on_the_commit_the_session_was_asked_to_fix
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'failure', pr_checks_at: NOW,
                                 pr_head_sha: 'a1b2c3', ci_repair_sha: 'a1b2c3', ci_repairs: 1)

      row = page.rows.fetch(0)

      assert_equal 'repairing', row.sla
      assert_equal 'sla-repairing', row.sla_class
      assert_equal '[REPAIRING]', row.sla_tag
      assert_equal 1, row.ci_repairs
      assert_predicate row, :ci_repairs?
      refute_predicate row, :breached?
    end

    def test_ci_failing_again_once_the_checks_are_red_on_a_commit_after_the_last_repair
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'failure', pr_checks_at: NOW,
                                 pr_head_sha: 'c3d4e5', ci_repair_sha: 'b2c3d4', ci_repairs: 2)

      row = page.rows.fetch(0)

      assert_equal 'ci failing', row.sla
      assert_equal '[CI FAILING]', row.sla_tag
      assert_equal 2, row.ci_repairs
    end

    def test_a_pull_request_closed_without_merging_is_neither_repairing_nor_ci_failing
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'closed',
                                 pr_notified_at: DUE - 3600, pr_checks: 'failure', pr_checks_at: NOW,
                                 pr_head_sha: 'a1b2c3', ci_repair_sha: 'a1b2c3', ci_repairs: 1)

      row = page.rows.fetch(0)

      refute_predicate row, :repairing?
      assert_equal 'in progress', row.sla
      assert_equal 1, row.ci_repairs

      DB[:sessions].update(ci_repairs: 0, ci_repair_sha: nil)

      assert_equal 'in progress', page.rows.fetch(0).sla
      assert_equal 'breached', page(now: DUE + 1).rows.fetch(0).sla
    end

    def test_repairs_do_not_change_the_word_while_checks_are_pending_green_or_past_due
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'pending', pr_checks_at: NOW,
                                 pr_head_sha: 'b2c3d4', ci_repair_sha: 'a1b2c3', ci_repairs: 1)

      assert_equal 'in progress', page.rows.fetch(0).sla

      DB[:sessions].update(pr_checks: 'success', pr_head_sha: 'a1b2c3')

      assert_equal 'met', page.rows.fetch(0).sla

      DB[:sessions].update(pr_checks: 'failure')

      assert_equal 'repairing', page.rows.fetch(0).sla
      assert_equal 'breached', page(now: DUE + 1).rows.fetch(0).sla
    end

    def test_breached_when_checks_are_still_red_past_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600, pr_checks: 'failure', pr_checks_at: DUE + 30)

      assert_equal 'breached', page(now: DUE + 60).rows.fetch(0).sla
    end

    def test_breached_when_a_pull_request_is_open_but_never_went_green_past_the_due_date
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: DUE - 3600)

      assert_equal 'breached', page(now: DUE + 60).rows.fetch(0).sla
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
      assert_nil row.time_to_pr
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

    def test_summary_counts_findings_and_the_two_sides_of_the_window
      record_session(record_finding(1, due_at: DUE), pr_url: 'https://github.com/x/y/pull/1', pr_state: 'open',
                                                     pr_notified_at: DUE - 60, pr_checks: 'success',
                                                     pr_checks_at: DUE - 30, outcome: 'settled')
      record_session(record_finding(2, due_at: DUE), pr_url: 'https://github.com/x/y/pull/2', pr_state: 'merged',
                                                     pr_notified_at: DUE + 60, pr_merged_at: DUE + 90,
                                                     outcome: 'settled')
      record_session(record_finding(3, due_at: NOW - 60), status: 'running', status_detail: 'working')
      record_session(record_finding(4, due_at: DUE), status: 'suspended', status_detail: 'inactivity',
                                                     outcome: 'stalled')
      record_finding(5, due_at: DUE)

      summary = page.summary

      assert_equal 5, summary.findings
      assert_equal 1, summary.fixed_inside_sla
      assert_equal 2, summary.breached
      assert_equal %w[breached met late stalled waiting], page.rows.map(&:sla)
    end

    def test_median_time_to_green_is_not_yet_before_any_pull_request_goes_green
      record_finding(1)

      assert_equal 'not yet', page.summary.median_time_to_green
    end

    def test_median_time_to_green_is_computed_from_dispatch_to_first_green
      record_session(record_finding(1), pr_url: 'https://github.com/x/y/pull/1', pr_state: 'merged',
                                        started_at: Time.utc(2026, 9, 2, 8, 0, 0), pr_merged_at: Time.utc(2026, 9, 2,
                                                                                                          8, 20, 0))
      record_session(record_finding(2), pr_url: 'https://github.com/x/y/pull/2', pr_state: 'open',
                                        started_at: Time.utc(2026, 9, 2, 8, 0, 0), pr_checks: 'success',
                                        pr_checks_at: Time.utc(2026, 9, 2, 8, 40, 0))

      assert_equal '30m 0s', page.summary.median_time_to_green
    end

    def test_row_strings_are_formatted_for_the_template
      finding_id = record_finding(8, fix_version: nil)
      record_session(finding_id, pr_url: 'https://github.com/kylesnowschwartz/superset/pull/9', pr_state: 'open',
                                 pr_notified_at: Time.utc(2026, 9, 2, 8, 44, 0), acus_consumed: 1.25,
                                 pr_checks: 'success', pr_checks_at: Time.utc(2026, 9, 2, 8, 44, 0))

      row = page.rows.fetch(0)

      assert_equal 8, row.issue_number
      assert_equal 'https://github.com/kylesnowschwartz/superset/issues/8', row.issue_url
      assert_equal '[SLA high] urllib3 2.4.0 → 2.7.0', row.issue_title
      assert_equal 'urllib3', row.package
      assert_equal '2.4.0 → no fix', row.versions
      assert_equal 'high', row.severity
      assert_equal 'pip-audit', row.source
      assert_equal '2026-09-02 08:25 UTC', row.filed
      assert_equal '2026-09-04 08:25 UTC', row.due
      assert_equal 'in 20h 25m', row.due_in
      assert_equal false, row.overdue?
      assert_equal '[MET]', row.sla_tag
      assert_equal 'f8', row.toggle_id
      assert_equal '18m 30s', row.time_to_pr
      assert_equal '1.25', row.acus
      assert_equal '2026-09-03 12:00 UTC', page.rendered_at
      assert_equal 'kylesnowschwartz/superset', page.repo
    end

    def test_fix_version_is_shown_when_present
      record_finding(1)

      assert_equal '2.4.0 → 2.7.0', page.rows.fetch(0).versions
      assert page.rows.fetch(0).fix_version?
    end

    def test_no_fix_text_is_the_single_source_of_the_no_fix_label
      record_finding(1, fix_version: nil)

      row = page.rows.fetch(0)

      refute row.fix_version?
      assert_equal 'no fix', row.no_fix_text
      assert_equal '2.4.0 → no fix', row.versions
    end

    def test_acus_are_not_reported_when_nil_or_zero
      record_session(record_finding(1), acus_consumed: nil)
      record_session(record_finding(2), acus_consumed: 0.0)

      assert_equal ['not reported', 'not reported'], page.rows.map(&:acus)
      assert_equal [false, false], page.rows.map(&:acus_reported?)
    end

    def test_acus_reported_is_true_once_a_nonzero_value_is_recorded
      record_session(record_finding(1), acus_consumed: 1.25)

      assert page.rows.fetch(0).acus_reported?
    end

    def test_a_pull_request_without_observed_checks_yet_is_in_progress_then_breached
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/x/y/pull/1', pr_state: 'open', pr_notified_at: nil)

      assert_equal 'in progress', page.rows.fetch(0).sla
      assert_equal 'breached', page(now: DUE + 1).rows.fetch(0).sla
      assert_nil page.rows.fetch(0).time_to_pr
    end

    def test_overdue_is_true_once_the_due_date_has_passed
      record_finding(1)

      assert_equal true, page(now: DUE + 1).rows.fetch(0).overdue?
      assert_equal false, page(now: DUE - 1).rows.fetch(0).overdue?
    end

    def test_overdue_depends_on_the_sla_word_not_only_on_the_clock
      finding_id = record_finding(1)
      record_session(finding_id, pr_url: 'https://github.com/x/y/pull/1', pr_state: 'merged',
                                 pr_notified_at: DUE - 3600, pr_merged_at: DUE - 1800, outcome: 'settled')

      row = page(now: DUE + 3600).rows.fetch(0)

      assert_equal 'met', row.sla
      assert_equal false, row.overdue?
    end

    def test_sla_tag_is_the_uppercase_bracketed_sla_word
      record_finding(1)

      assert_equal '[WAITING]', page.rows.fetch(0).sla_tag

      finding_id = record_finding(2)
      record_session(finding_id, status: 'running', status_detail: 'working')

      assert_equal '[IN PROGRESS]', page.rows.fetch(1).sla_tag
    end

    def test_advisories_are_comma_joined_and_nil_when_absent
      finding_id = record_finding(1)
      DB[:findings].where(id: finding_id).update(advisories: '["GHSA-a", "GHSA-b"]')

      assert_equal 'GHSA-a, GHSA-b', page.rows.fetch(0).advisories

      DB[:findings].where(id: finding_id).update(advisories: nil)

      assert_nil page.rows.fetch(0).advisories
    end

    def test_lockfile_reads_the_structured_output_and_is_nil_before_a_report
      finding_id = record_finding(1)
      record_session(finding_id, structured_output: JSON.generate(
        lockfile_route: 'direct_edit', verification: { tool: 'pip-audit', clean: true }
      ))

      assert_equal 'direct_edit · pip-audit clean', page.rows.fetch(0).lockfile

      finding_id2 = record_finding(2)
      record_session(finding_id2)

      assert_nil page.rows.find { |row| row.issue_number == 2 }.lockfile
    end

    def test_lockfile_reports_not_clean_when_verification_failed
      finding_id = record_finding(1)
      record_session(finding_id, structured_output: JSON.generate(
        lockfile_route: 'recompile', verification: { tool: 'pip-audit', clean: false }
      ))

      assert_equal 'recompile · pip-audit not clean', page.rows.fetch(0).lockfile
    end

    def test_lockfile_reports_a_rejected_report_when_the_schema_did_not_validate
      finding_id = record_finding(1)
      record_session(finding_id, structured_output: nil, structured_output_invalid: JSON.generate(package: 'urllib3'))

      assert_equal 'report rejected (schema)', page.rows.fetch(0).lockfile
    end

    def test_checks_line_shows_the_check_state_and_when_it_was_observed
      record_finding(1)

      refute page.rows.fetch(0).checks?

      finding_id = record_finding(2)
      record_session(finding_id, pr_url: 'https://github.com/x/y/pull/1', pr_state: 'open', pr_checks: 'pending',
                                 pr_checks_at: Time.utc(2026, 9, 2, 8, 44, 0))

      row = page.rows.find { |r| r.issue_number == 2 }

      assert row.checks?
      assert_equal 'pending', row.checks
      assert_equal '2026-09-02 08:44 UTC', row.checks_observed_at

      finding_id2 = record_finding(3)
      record_session(finding_id2, pr_url: 'https://github.com/x/y/pull/2', pr_state: 'merged',
                                  pr_checks: 'success', pr_checks_at: Time.utc(2026, 9, 2, 8, 44, 0),
                                  pr_merged_at: Time.utc(2026, 9, 2, 9, 0, 0))

      row3 = page.rows.find { |r| r.issue_number == 3 }

      assert_equal '2026-09-02 09:00 UTC', row3.checks_observed_at
    end

    def test_session_status_reads_status_slash_detail_and_the_outcome
      finding_id = record_finding(1)
      record_session(finding_id, status: 'running', status_detail: 'finished', outcome: 'settled')

      assert_equal 'running/finished → settled', page.rows.fetch(0).session_status
    end

    def test_session_status_omits_the_outcome_before_the_session_closes
      finding_id = record_finding(1)
      record_session(finding_id, status: 'running', status_detail: 'working')

      assert_equal 'running/working', page.rows.fetch(0).session_status
    end

    def test_session_helpers_reflect_whether_a_session_was_dispatched
      record_finding(1)

      refute page.rows.fetch(0).session?
      assert_nil page.rows.fetch(0).started
      assert_nil page.rows.fetch(0).time_to_pr

      finding_id = record_finding(2)
      record_session(finding_id, pr_notified_at: Time.utc(2026, 9, 2, 8, 44, 0))

      row = page.rows.find { |r| r.issue_number == 2 }

      assert row.session?
      assert_equal '2026-09-02 08:25 UTC', row.started
      refute_nil row.time_to_pr
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
