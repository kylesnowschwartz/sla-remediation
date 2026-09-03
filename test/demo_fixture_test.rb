# frozen_string_literal: true

require 'stringio'

require_relative 'test_helper'

module SLA
  class DemoFixtureTest < Minitest::Test
    CAPTURED = Time.utc(2026, 9, 2, 9, 0, 0)
    LOADED = Time.utc(2026, 9, 9, 15, 30, 0)
    ISSUE_URL = 'https://github.com/kylesnowschwartz/superset/issues'
    PULL_URL = 'https://github.com/kylesnowschwartz/superset/pull'

    def setup
      DB[:sessions].delete
      DB[:findings].delete
      @out = StringIO.new
    end

    def test_export_writes_every_row_of_both_tables_with_iso_8601_utc_timestamps
      record_run

      fixture = JSON.parse(fixture_for.export(now: CAPTURED).to_json)

      assert_equal %w[note exported_at findings sessions], fixture.keys
      assert_includes fixture['note'], 'Nothing here is secret'
      assert_includes fixture['note'], '2026-09-02T09:00:00Z'
      assert_equal '2026-09-02T09:00:00Z', fixture['exported_at']
      assert_equal 4, fixture['findings'].size
      assert_equal 3, fixture['sessions'].size
      assert_equal DB.schema(:findings).map { |column, _| column.to_s }, fixture['findings'].first.keys
      assert_equal DB.schema(:sessions).map { |column, _| column.to_s }, fixture['sessions'].first.keys
      met = fixture['findings'].find { |row| row['issue_number'] == 1 }
      assert_equal '2026-09-04T08:25:30.000000Z', met['due_at']
      assert_equal 'https://github.com/kylesnowschwartz/superset/issues/1', met['issue_url']
      session = fixture['sessions'].find { |row| row['finding_id'] == met['id'] }
      assert_equal '2026-09-02T08:44:00.000000Z', session['pr_checks_at']
      assert_nil session['pr_merged_at']
      assert_equal 1.25, session['acus_consumed']
      assert_equal "exported 4 findings\nexported 3 sessions\n", @out.string
    end

    def test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later
      fixture = exported_run
      assert_equal %w[breached late met waiting], page(now: CAPTURED).rows.map(&:sla)
      clear

      summary = fixture_for.load(fixture, now: LOADED)

      assert_equal 4, summary[:findings]
      assert_equal 3, summary[:sessions]
      assert_equal (LOADED - Time.utc(2026, 9, 2, 8, 50, 0)).to_i, summary[:shift_seconds]
      assert_equal %w[breached late met waiting], page(now: LOADED).rows.map(&:sla)
      assert_equal %w[breached late met waiting], page(now: LOADED + (3 * 86_400)).rows.map(&:sla)
      assert_equal LOADED, DB[:sessions].select_map(:pr_merged_at).compact.max
      assert_equal "loaded 4 findings\nloaded 3 sessions\nshifted every timestamp forward by 7d 6h\n", @out.string
    end

    def test_load_keeps_every_interval_between_events
      fixture = exported_run
      before = intervals
      clear

      fixture_for.load(fixture, now: LOADED)

      assert_equal before, intervals
      assert_equal '18m 30s', page(now: LOADED).rows.find { |row| row.issue_number == 1 }.time_to_pr
    end

    def test_load_refuses_when_a_table_already_has_rows
      fixture = exported_run
      clear
      DB[:findings].insert(issue_number: 99, created_at: LOADED, due_at: LOADED)

      error = assert_raises(DemoFixture::DatabaseNotEmpty) { fixture_for.load(fixture, now: LOADED) }

      assert_equal 'database already has 1 findings and 0 sessions; pass --replace to empty both tables first',
                   error.message
      assert_equal [99], DB[:findings].select_map(:issue_number)
      assert_equal '', @out.string
    end

    def test_load_with_replace_empties_both_tables_first
      fixture = exported_run

      summary = fixture_for.load(fixture, now: LOADED, replace: true)

      assert_equal 4, summary[:findings]
      assert_equal [1, 2, 3, 4], DB[:findings].order(:issue_number).select_map(:issue_number)
      assert_equal 3, DB[:sessions].count
      assert_equal "deleted 3 sessions and 4 findings\nloaded 4 findings\nloaded 3 sessions\n" \
                   "shifted every timestamp forward by 7d 6h\n", @out.string
    end

    def test_load_without_any_check_or_merge_time_anchors_on_the_newest_timestamp
      record_finding(1, created_at: CAPTURED - 7200, due_at: CAPTURED + 3600)
      fixture = fixture_for.export(now: CAPTURED)
      clear

      fixture_for.load(fixture, now: LOADED)

      assert_equal LOADED, DB[:findings].get(:due_at)
      assert_equal LOADED - 10_800, DB[:findings].get(:created_at)
    end

    def test_load_of_an_empty_fixture_inserts_nothing
      summary = fixture_for.load({ 'findings' => [], 'sessions' => [] }, now: LOADED)

      assert_equal({ findings: 0, sessions: 0, shift_seconds: 0 }, summary)
      assert_equal 0, DB[:findings].count
    end

    private

    def fixture_for
      DemoFixture.new(DB, out: @out)
    end

    def exported_run
      record_run
      fixture = JSON.parse(DemoFixture.new(DB, out: StringIO.new).export(now: CAPTURED).to_json)
      @out.truncate(0)
      @out.rewind
      fixture
    end

    def clear
      DB[:sessions].delete
      DB[:findings].delete
    end

    def page(now:)
      StatusPage.new(DB, repo: 'kylesnowschwartz/superset', now: now)
    end

    # Every timestamp in both tables relative to the earliest one, so the
    # shape of the run can be compared before and after a shift.
    def intervals
      times = DB[:findings].order(:issue_number).all.flat_map { |row| row.values_at(:created_at, :due_at) } +
              DB[:sessions].order(:finding_id).all.flat_map do |row|
                row.values_at(:started_at, :pr_notified_at, :pr_checks_at, :pr_merged_at)
              end
      first = times.compact.min
      times.map { |time| time && (time - first).round(3) }
    end

    # One run as the tracker leaves it, captured at CAPTURED: a breached
    # finding with a stalled session, a pull request green inside the window,
    # a pull request merged after the window, and a finding with no fix.
    def record_run
      due = Time.utc(2026, 9, 4, 8, 25, 30)
      record_session(record_finding(1, due_at: due),
                     pr_url: "#{PULL_URL}/9", pr_state: 'open', started_at: Time.utc(2026, 9, 2, 8, 25, 30),
                     pr_notified_at: Time.utc(2026, 9, 2, 8, 44, 0), pr_checks: 'success',
                     pr_checks_at: Time.utc(2026, 9, 2, 8, 44, 0), acus_consumed: 1.25, outcome: 'settled')
      record_session(record_finding(2, severity: 'critical', due_at: Time.utc(2026, 9, 2, 8, 40, 0)),
                     pr_url: "#{PULL_URL}/10", pr_state: 'merged', started_at: Time.utc(2026, 9, 2, 8, 26, 0),
                     pr_notified_at: Time.utc(2026, 9, 2, 8, 45, 0), pr_merged_at: Time.utc(2026, 9, 2, 8, 50, 0),
                     outcome: 'settled')
      record_session(record_finding(3, severity: 'critical', due_at: Time.utc(2026, 9, 2, 8, 30, 0)),
                     status: 'suspended', status_detail: 'inactivity', outcome: 'stalled')
      record_finding(4, severity: 'low', fix_version: nil, due_at: Time.utc(2026, 9, 16, 8, 25, 30))
    end

    def record_finding(number, severity: 'high', fix_version: '2.7.0', due_at: Time.utc(2026, 9, 4, 8, 25, 30),
                       created_at: Time.utc(2026, 9, 2, 8, 25, 30))
      DB[:findings].insert(issue_number: number, issue_url: "#{ISSUE_URL}/#{number}",
                           issue_title: "[SLA #{severity}] urllib3 2.4.0 → #{fix_version || 'no fix'}",
                           package: 'urllib3', pinned: '2.4.0', fix_version: fix_version, severity: severity,
                           source: 'pip-audit', advisories: %w[GHSA-48p4-8xcf-vxj5].to_json,
                           opened_at: created_at, due_at: due_at, created_at: created_at)
    end

    def record_session(finding_id, **columns)
      DB[:sessions].insert({ finding_id: finding_id, devin_session_id: "session-#{finding_id}", status: 'exit',
                             status_detail: 'finished', last_polled_at: CAPTURED }.merge(columns))
    end
  end
end
