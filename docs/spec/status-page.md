# Status page

`GET /` renders SLA status from the findings and sessions tables; all decisions are made in Ruby, the template only prints.

## The page

- **PAGE-01** `GET /` answers 200 with an HTML page that reloads itself every 15 seconds.
- **PAGE-02** Shows the target repository's name and the time the page was rendered.
- **PAGE-03** One summary line:
  - findings tracked
  - findings whose SLA word is `met` ("fixed inside SLA")
  - findings whose SLA word is `breached` or `late`
  - median time from a session's start to its pull request turning green (merged, or checks last passing)
  - `not yet` before any pull request has gone green
- **PAGE-04** One row per finding, by severity `critical`/`high`/`medium`/`low`/other, then earliest due.
- **PAGE-05** Serves the stylesheet at `/house-style.css`.

## The SLA word

First rule that applies wins.

- **PAGE-06** Pull request merged, or checks `success`, at or before the due date → `met`.
- **PAGE-07** Pull request green (merged or checks passed) after the due date → `late`.
- **PAGE-07A** Checks `pending` or not yet observed, or the pull request `closed` unmerged, due date not passed → `in progress`.
- **PAGE-07B** Open pull request, checks `failure` at the sha last sent back to the session (`ci_repairs` above 0, `ci_repair_sha` equal to `pr_head_sha`), inside the window → `repairing`.
  - tagged `[REPAIRING]`, coloured as `in progress`
  - checks next observed `failure` on a later sha → `ci failing` again (PAGE-08)
  - a pull request closed without merging is never `repairing`, whatever its shas say
- **PAGE-08** Open pull request, checks `failure` inside the window, PAGE-07B not applying → `ci failing`.
  - tagged `[CI FAILING]`, coloured as `breached`/`late`
- **PAGE-09** No green pull request past the due date → `breached`, whatever the checks say or if stalled.
- **PAGE-10** No pull request, due date not passed, session outcome `stalled` → `stalled`.
- **PAGE-11** Sessions row but no pull request, inside the window → `in progress`, session id or not.
- **PAGE-12** No pull request, no sessions row, inside the window → `waiting`.

## The cells

- **PAGE-13** Filed and due times read `YYYY-MM-DD HH:MM UTC`.
- **PAGE-14** Distance to the due date reads `in <duration>` before it, `<duration> ago` after.
- **PAGE-15** Durations: `Ns` under a minute, `Nm Ns` under an hour, `Nh Nm` under a day, `Nd Nh` above.
  - fractional seconds are rounded
- **PAGE-16** Package reads `<pinned> → <fix_version>`, or `<pinned> → no fix` without a fix version.
- **PAGE-17** Devin cell: `not dispatched` with no row, else the outcome, else `<status>/<status_detail>`.
  - links to the Devin session only when the row has a session id
- **PAGE-18** Pull request cell: the number, linked, and its state, or a dash when there is none.
- **PAGE-19** Detail row: session start → pull request first sighting; omitted if a time is missing.
- **PAGE-20** With a session, ACUs consumed, or `not reported` when absent or 0.0; no session → omitted.

## The detail row

- **PAGE-21** Each finding's row has a detail row below it, collapsed until its toggle is activated.
- **PAGE-22** Always shows the finding's title and the time it was filed.
- **PAGE-23** Advisories comma-joined; the line is omitted when there are none.
- **PAGE-24** Shows the finding's source when it has one.
- **PAGE-25** Session: linked id, `<status>/<status_detail>`, `→ <outcome>` once closed; else `none`.
- **PAGE-26** Session start time when it has started; the line is omitted otherwise.
- **PAGE-27** By structured output:
  - valid → lockfile route and the verification tool's clean/not-clean result
  - failed schema validation → `report rejected (schema)`
  - none → line omitted
- **PAGE-28** Observed checks → the check state and when it (or the merge) was observed; else omitted.
- **PAGE-29** `ci_repairs` above 0 → `ci repairs: N`; none sent → line omitted.

## Not specified

- Layout, colours, fonts, and markup; only the text and links above are promised.
- Column headings and the dash character used for an empty cell.
- Behaviour when `SLA_REPO` is unset; the page renders with an empty name.

<details><summary>Proofs</summary>

- PAGE-01: `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself
- PAGE-02: `test/status_page_test.rb` test_row_strings_are_formatted_for_the_template; `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself
- PAGE-03: `test/status_page_test.rb` test_summary_counts_findings_and_the_two_sides_of_the_window, test_median_time_to_green_is_not_yet_before_any_pull_request_goes_green, test_median_time_to_green_is_computed_from_dispatch_to_first_green
- PAGE-04: `test/status_page_test.rb` test_rows_are_sorted_by_severity_then_by_due_date
- PAGE-05: `test/app_test.rb` test_house_style_is_served
- PAGE-06: `test/status_page_test.rb` test_met_when_the_pull_request_merged_before_the_due_date, test_met_when_the_pull_request_checks_went_green_before_the_due_date
- PAGE-07: `test/status_page_test.rb` test_late_when_the_pull_request_merged_after_the_due_date
- PAGE-07A: `test/status_page_test.rb` test_in_progress_when_the_pull_requests_checks_are_pending, test_a_pull_request_without_observed_checks_yet_is_in_progress_then_breached, test_a_pull_request_closed_without_merging_is_neither_repairing_nor_ci_failing
- PAGE-07B: `test/status_page_test.rb` test_repairing_when_checks_are_red_on_the_commit_the_session_was_asked_to_fix, test_ci_failing_again_once_the_checks_are_red_on_a_commit_after_the_last_repair, test_repairs_do_not_change_the_word_while_checks_are_pending_green_or_past_due, test_a_pull_request_closed_without_merging_is_neither_repairing_nor_ci_failing; `test/app_test.rb` test_status_page_shows_a_pull_request_the_session_is_repairing
- PAGE-08: `test/status_page_test.rb` test_ci_failing_when_checks_are_red_inside_the_window, test_ci_failing_again_once_the_checks_are_red_on_a_commit_after_the_last_repair, test_a_pull_request_closed_without_merging_is_neither_repairing_nor_ci_failing
- PAGE-09: `test/status_page_test.rb` test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed, test_breached_takes_precedence_over_a_stalled_session_once_the_due_date_has_passed, test_breached_when_checks_are_still_red_past_the_due_date, test_breached_when_a_pull_request_is_open_but_never_went_green_past_the_due_date, test_a_pull_request_without_observed_checks_yet_is_in_progress_then_breached
- PAGE-10: `test/status_page_test.rb` test_stalled_when_the_session_stopped_without_a_pull_request_inside_the_window
- PAGE-11: `test/status_page_test.rb` test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window, test_a_reserved_session_row_without_a_devin_session_id_counts_as_in_progress_without_a_link
- PAGE-12: `test/status_page_test.rb` test_waiting_when_nothing_has_been_dispatched_inside_the_window
- PAGE-13: `test/status_page_test.rb` test_row_strings_are_formatted_for_the_template
- PAGE-14: `test/status_page_test.rb` test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window, test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed
- PAGE-15: `test/status_page_test.rb` test_duration_reads_in_seconds_minutes_hours_or_days
- PAGE-16: `test/status_page_test.rb` test_fix_version_is_shown_when_present, test_row_strings_are_formatted_for_the_template
- PAGE-17: `test/status_page_test.rb` test_waiting_when_nothing_has_been_dispatched_inside_the_window, test_met_when_the_pull_request_merged_before_the_due_date, test_breached_when_there_is_no_pull_request_and_the_due_date_has_passed, test_a_reserved_session_row_without_a_devin_session_id_counts_as_in_progress_without_a_link
- PAGE-18: `test/status_page_test.rb` test_met_when_the_pull_request_merged_before_the_due_date; `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself
- PAGE-19: `test/status_page_test.rb` test_row_strings_are_formatted_for_the_template, test_in_progress_when_a_session_exists_without_a_pull_request_inside_the_window, test_a_pull_request_without_observed_checks_yet_is_in_progress_then_breached
- PAGE-20: `test/status_page_test.rb` test_acus_are_not_reported_when_nil_or_zero, test_acus_reported_is_true_once_a_nonzero_value_is_recorded, test_row_strings_are_formatted_for_the_template; `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself
- PAGE-21: `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself
- PAGE-22: `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself; `test/status_page_test.rb` test_row_strings_are_formatted_for_the_template
- PAGE-23: `test/status_page_test.rb` test_advisories_are_comma_joined_and_nil_when_absent
- PAGE-24: `test/status_page_test.rb` test_row_strings_are_formatted_for_the_template
- PAGE-25: `test/status_page_test.rb` test_session_status_reads_status_slash_detail_and_the_outcome, test_session_status_omits_the_outcome_before_the_session_closes; `test/app_test.rb` test_status_page_lists_the_findings_and_refreshes_itself
- PAGE-26: `test/status_page_test.rb` test_session_helpers_reflect_whether_a_session_was_dispatched
- PAGE-27: `test/status_page_test.rb` test_lockfile_reads_the_structured_output_and_is_nil_before_a_report, test_lockfile_reports_not_clean_when_verification_failed, test_lockfile_reports_a_rejected_report_when_the_schema_did_not_validate
- PAGE-28: `test/status_page_test.rb` test_checks_line_shows_the_check_state_and_when_it_was_observed
- PAGE-29: `test/status_page_test.rb` test_repairing_when_checks_are_red_on_the_commit_the_session_was_asked_to_fix, test_ci_failing_when_checks_are_red_inside_the_window; `test/app_test.rb` test_status_page_shows_a_pull_request_the_session_is_repairing, test_status_page_lists_the_findings_and_refreshes_itself

</details>
