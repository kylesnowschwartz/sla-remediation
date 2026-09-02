# Status page

`GET /` answers the question "are we meeting the security SLA, and what is
Devin doing about what is open?" from the findings and sessions tables. All
decisions are made in Ruby; the template only prints.

## The page

**PAGE-01** THE service SHALL answer `GET /` with 200 and an HTML page that
reloads itself every 15 seconds.
Proof: test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself

**PAGE-02** THE page SHALL show the target repository's name and the time it
was rendered.
Proof: test/status_page_test.rb test_row_strings_are_formatted_for_the_template;
test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself

**PAGE-03** THE page SHALL show four counts: findings tracked, pull requests
whose state is `open`, findings whose SLA word is not `breached` or `late`,
and findings whose SLA word is `breached` or `late`.
Proof: test/status_page_test.rb test_summary_counts_findings_open_pull_requests_and_the_two_sides_of_the_window

**PAGE-04** THE page SHALL list one row per finding, ordered by severity
(`critical`, `high`, `medium`, `low`, then anything else) and within a
severity by due date, soonest first.
Proof: test/status_page_test.rb test_rows_are_sorted_by_severity_then_by_due_date

**PAGE-05** THE service SHALL serve the stylesheet at `/house-style.css`.
Proof: test/app_test.rb test_house_style_is_served

## The SLA word

Decided in this order; the first rule that applies wins.

**PAGE-06** IF the finding has a pull request and the tracker first saw it
at or before the due date, THEN the word SHALL be `met`.
Proof: test/status_page_test.rb test_met_when_the_pull_request_was_seen_before_the_due_date

**PAGE-07** IF the finding has a pull request and the tracker first saw it
after the due date, THEN the word SHALL be `late`.
Proof: test/status_page_test.rb test_late_when_the_pull_request_was_seen_after_the_due_date

**PAGE-08** IF the finding has a pull request but its first-seen time is
cleared because the issue comment is being retried, THEN the page SHALL
judge `met` or `late` by the current time.
Proof: test/status_page_test.rb test_a_pull_request_whose_comment_is_being_retried_is_judged_by_now

**PAGE-09** IF there is no pull request and now is after the due date, THEN
the word SHALL be `breached`, even when the session stalled.
Proof: test/status_page_test.rb test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed,
test_breached_takes_precedence_over_a_stalled_session_once_the_due_date_has_passed

**PAGE-10** IF there is no pull request, the due date has not passed, and
the session's outcome is `stalled`, THEN the word SHALL be `stalled`.
Proof: test/status_page_test.rb test_stalled_when_the_session_stopped_without_a_pull_request_inside_the_window

**PAGE-11** IF there is no pull request, the due date has not passed, and a
sessions row exists (even one reserved without a Devin session id yet),
THEN the word SHALL be `in progress`.
Proof: test/status_page_test.rb test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window,
test_a_reserved_session_row_without_a_devin_session_id_counts_as_in_progress_without_a_link

**PAGE-12** IF there is no pull request, no sessions row, and the due date
has not passed, THEN the word SHALL be `waiting`.
Proof: test/status_page_test.rb test_waiting_when_nothing_has_been_dispatched_inside_the_window

## The cells

**PAGE-13** THE page SHALL show filed and due times as `YYYY-MM-DD HH:MM UTC`.
Proof: test/status_page_test.rb test_row_strings_are_formatted_for_the_template

**PAGE-14** THE page SHALL show how far the due date is as `in <duration>`
before it and `<duration> ago` after it.
Proof: test/status_page_test.rb test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window,
test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed

**PAGE-15** THE page SHALL write durations as `Ns` under a minute, `Nm Ns`
under an hour, `Nh Nm` under a day, and `Nd Nh` from a day up, rounding
fractional seconds.
Proof: test/status_page_test.rb test_duration_reads_in_seconds_minutes_hours_or_days

**PAGE-16** THE page SHALL show the package as `<pinned> → <fix_version>`,
or `<pinned> → no fix` when there is no fix version.
Proof: test/status_page_test.rb test_fix_version_is_shown_when_present,
test_row_strings_are_formatted_for_the_template

**PAGE-17** THE Devin cell SHALL read `not dispatched` when there is no
sessions row, the outcome once there is one, and otherwise
`<status>/<status_detail>`; it SHALL link to the Devin session when the row
has a session id and not otherwise.
Proof: test/status_page_test.rb test_waiting_when_nothing_has_been_dispatched_inside_the_window,
test_met_when_the_pull_request_was_seen_before_the_due_date,
test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed,
test_a_reserved_session_row_without_a_devin_session_id_counts_as_in_progress_without_a_link

**PAGE-18** THE pull request cell SHALL show the pull request number, linked,
and its state, or a dash when there is none.
Proof: test/status_page_test.rb test_met_when_the_pull_request_was_seen_before_the_due_date;
test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself

**PAGE-19** THE detail row SHALL show the duration from the session's start
to the tracker's first sighting of the pull request, omitting the line
entirely when either time is missing.
Proof: test/status_page_test.rb test_row_strings_are_formatted_for_the_template,
test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window,
test_a_pull_request_whose_comment_is_being_retried_is_judged_by_now

**PAGE-20** IF the finding has a session, THEN the detail row SHALL show
the ACUs consumed, or `not reported` when it is absent or exactly 0.0; IF
there is no session, THEN the line SHALL be omitted.
Proof: test/status_page_test.rb test_acus_are_not_reported_when_nil_or_zero,
test_acus_reported_is_true_once_a_nonzero_value_is_recorded,
test_row_strings_are_formatted_for_the_template;
test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself

## The detail row

**PAGE-21** THE page SHALL show, under each finding's row, one detail row
that starts collapsed and expands only once its toggle is activated.
Proof: test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself

**PAGE-22** THE detail row SHALL always show the finding's title and the
time it was filed.
Proof: test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself;
test/status_page_test.rb test_row_strings_are_formatted_for_the_template

**PAGE-23** IF the finding has advisories, THEN the detail row SHALL show
them comma-joined; IF it has none, THEN the line SHALL be omitted.
Proof: test/status_page_test.rb test_advisories_are_comma_joined_and_nil_when_absent

**PAGE-24** IF the finding has a source, THEN the detail row SHALL show it.
Proof: test/status_page_test.rb test_row_strings_are_formatted_for_the_template

**PAGE-25** IF the finding has a session, THEN the detail row SHALL show
the session id linked to the Devin session and `<status>/<status_detail>`,
followed by `→ <outcome>` once the session has closed; IF it has none,
THEN the line SHALL read `none`.
Proof: test/status_page_test.rb test_session_status_reads_status_slash_detail_and_the_outcome,
test_session_status_omits_the_outcome_before_the_session_closes;
test/app_test.rb test_status_page_lists_the_findings_and_refreshes_itself

**PAGE-26** IF the session has started, THEN the detail row SHALL show the
time it started; IF it has not, THEN the line SHALL be omitted.
Proof: test/status_page_test.rb test_session_helpers_reflect_whether_a_session_was_dispatched

**PAGE-27** IF the session reported structured output that matched its
schema, THEN the detail row SHALL show the lockfile route and the
verification tool's clean or not-clean result; IF the session reported
structured output that failed schema validation, THEN it SHALL show
`report rejected (schema)`; IF neither, THEN the line SHALL be omitted.
Proof: test/status_page_test.rb test_lockfile_reads_the_structured_output_and_is_nil_before_a_report,
test_lockfile_reports_not_clean_when_verification_failed,
test_lockfile_reports_a_rejected_report_when_the_schema_did_not_validate

## Unproven

None.

## Not specified

- Layout, colours, fonts, and markup; only the text and links above are
  promised.
- Column headings and the dash character used for an empty cell.
- Behaviour when `SLA_REPO` is unset; the page renders with an empty name.
