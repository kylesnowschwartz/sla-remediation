# Track

The tracker polls open Devin sessions, records what it sees, announces the pull request once, then follows that pull request on GitHub until it is merged, closed, or green, sending red checks back to the session that opened it.

## What is polled and recorded

- **TRACK-01** Polls every sessions row with a Devin session id and no outcome, oldest row first.
- **TRACK-02** Outcome set → session never fetched again; its pull request may still be followed (TRACK-22).
- **TRACK-03** On fetch, records status, status detail, ACUs, poll time, and its first pull request's URL and state.
- **TRACK-04** Output matching the remediation result schema is stored as JSON in `structured_output`.
- **TRACK-05** Off-schema output → JSON in `structured_output_invalid`, warning names the first problem, nothing lost.
- **TRACK-06** Reads the API's output as an object or as a JSON string; `"null"` or absent means no output.
- **TRACK-07** A change of status or status detail is logged once, naming the issue and session.

## Deciding the outcome

- **TRACK-08** *Stopped*: status `exit`/`error`, or detail `waiting_for_user`/`finished`/`inactivity`.
- **TRACK-09** A session is *reported* when it has structured output or a pull request.
- **TRACK-10** Stopped and reported → outcome `reported`, finished at the session's last update time.
- **TRACK-11** Stopped but not reported → outcome `stalled`; warning logged naming issue, session, status.
- **TRACK-12** While not stopped, the row stays open: no outcome, no finish time.

## Telling the issue

- **TRACK-13** A row's first pull request URL → stamp `pr_notified_at`, then announce the pull request, once.
- **TRACK-14** Failed announcement → clear `pr_notified_at`, row stays open, error counted, retried next poll.
- **TRACK-15** Notifier comments once: pull request and session URLs, due `YYYY-MM-DD HH:MM UTC`, inside or past SLA.
- **TRACK-16** Without `SLA_GITHUB_TOKEN`: notifier posts nothing, GitHub never asked about pull requests.

## Following the pull request

- **TRACK-22** Asks GitHub about the PR every poll while open, then every round until merged, closed, or green.
- **TRACK-23** GitHub's answer wins: state `merged`/`closed`/`open`, merge time once, check state over every run on the head commit —
  - runs read page by page until GitHub's `total_count` is reached or a page comes back empty
  - `success`: every completed run passed, was neutral, or was skipped
  - `failure`: any run failed
  - `pending`: any run unfinished
  - `none`: no runs
- **TRACK-24** Times are GitHub's own, not when the tracker noticed:
  - merge `merged_at`; completed checks, the latest `completed_at` among the runs
  - checks `pending` or `none`: the time the tracker saw them
- **TRACK-25** While the check state is unchanged, the check time is left alone.
- **TRACK-26** Checks turning `failure` from any other state → logged once, naming issue and pull request.
- **TRACK-27** A GitHub failure, or a pull request URL off GitHub, is logged and counted:
  - the row's pull request columns stay as they were
  - the same poll still announces the pull request and decides the outcome

## Sending red checks back to the session

- **TRACK-28** Open pull request, checks `failure` at a head sha other than the row's `ci_repair_sha` → the failed runs go to the session that opened it, as a message; no new session:
  - failed runs taken from the runs already read for TRACK-23 (no second fetch): conclusions `failure`/`timed_out`/`cancelled`/`action_required`
  - each run's name, `details_url`, and the first 40 lines of `output.summary`, else `output.text`; job logs are not downloaded
  - message rendered from `prompts/repair_ci.md.erb` with the pull request URL, branch, sha, and those runs
- **TRACK-29** Message sent → sha recorded as `ci_repair_sha`, `ci_repairs` incremented; same sha red again → no second message, however many rounds.
- **TRACK-30** A new red sha with `ci_repairs` below `MAX_CI_REPAIRS` (2) → another message; at the cap → logged once per red sha, nothing sent, columns unchanged.
- **TRACK-31** Sending fails → error counted, check state kept, `ci_repair_sha`/`ci_repairs` unchanged, retried next round.
- **TRACK-32** A merged or closed pull request is never messaged, whatever its checks say.
- **TRACK-33** While the session is `running` and not stopped (TRACK-08) → red checks recorded, nothing sent or counted, logged once per red sha; the message goes the round the session stops.

## The polling round and command

- **TRACK-17** A failed session poll is logged and counted; the round continues with the remaining sessions.
- **TRACK-18** Each round summarises polled, reported, stalled, notified, and errors from polls and PR checks.
- **TRACK-19** Run as a loop: poll, report the round, sleep the interval, repeat until stopped.
- **TRACK-20** `bin/track` runs one round; `bin/track --loop` repeats every 15 seconds until interrupted.
  - Summary line: `polled= reported= stalled= notified= errors=`
- **TRACK-21** Missing `DEVIN_SERVICE_API_KEY_V3` or `DEVIN_ORG_ID` → names them, exits 1 without polling.

## Not specified

- The wording of log lines.
- Legacy commit statuses; only the Checks API.
- Green-then-red pull requests: the tracker records the latest state, the status page spec rules.
- Whether a stored valid structured output is ever replaced; the first is kept, but untested.
- Resuming, terminating, or archiving sessions; the tracker's only write to Devin is the repair message of TRACK-28, which relies on the session being `resumable` (DISP-06).
- The wording of the repair message beyond what TRACK-28 names; the template is the artifact.

<details><summary>Proofs</summary>

- TRACK-01: `test/tracker_test.rb` test_working_session_stays_open, test_rows_without_a_devin_session_id_are_skipped
- TRACK-02: `test/tracker_test.rb` test_reported_session_with_pull_request_and_output_is_recorded_and_notified_once, test_suspended_session_without_report_or_pull_request_is_stalled, test_a_reported_row_with_pending_checks_is_watched_until_they_pass
- TRACK-03: `test/tracker_test.rb` test_reported_session_with_pull_request_and_output_is_recorded_and_notified_once, test_working_session_stays_open
- TRACK-04: `test/tracker_test.rb` test_reported_session_with_pull_request_and_output_is_recorded_and_notified_once
- TRACK-05: `test/tracker_test.rb` test_output_of_another_shape_is_kept_as_invalid_with_a_warning
- TRACK-06: `test/devin_client_test.rb` test_structured_output_object_stays_a_hash, test_structured_output_json_string_is_parsed, test_structured_output_string_null_becomes_nil
- TRACK-07: `test/tracker_test.rb` test_a_status_change_is_logged_once
- TRACK-08: `test/devin_client_test.rb` test_running_session_is_not_stopped, test_waiting_for_user_with_output_is_reported, test_suspended_with_pr_is_stopped_and_reported
- TRACK-09: `test/devin_client_test.rb` test_waiting_for_user_with_output_is_reported, test_suspended_with_pr_is_stopped_and_reported
- TRACK-10: `test/tracker_test.rb` test_reported_session_with_pull_request_and_output_is_recorded_and_notified_once, test_suspended_session_with_pull_request_is_reported_and_notified_once, test_output_of_another_shape_is_kept_as_invalid_with_a_warning
- TRACK-11: `test/tracker_test.rb` test_suspended_session_without_report_or_pull_request_is_stalled; `test/devin_client_test.rb` test_stopped_without_output_or_pr_is_stalled
- TRACK-12: `test/tracker_test.rb` test_working_session_stays_open
- TRACK-13: `test/tracker_test.rb` test_reported_session_with_pull_request_and_output_is_recorded_and_notified_once, test_suspended_session_with_pull_request_is_reported_and_notified_once, test_a_failed_notification_clears_the_timestamp_and_leaves_the_row_open
- TRACK-14: `test/tracker_test.rb` test_a_failed_notification_clears_the_timestamp_and_leaves_the_row_open
- TRACK-15: `test/notifier_test.rb` test_issue_comment_posts_the_links_and_inside_the_window, test_issue_comment_says_past_the_window_after_the_due_date
- TRACK-16: `test/notifier_test.rb` test_null_posts_nothing; `test/tracker_test.rb` test_without_a_github_client_pull_requests_are_never_looked_at (the wiring in `bin/track` is unproven)
- TRACK-17: `test/tracker_test.rb` test_an_error_for_one_session_does_not_stop_the_others
- TRACK-18: `test/tracker_test.rb` test_an_error_for_one_session_does_not_stop_the_others, test_a_github_error_while_checking_the_pull_request_is_counted_and_leaves_the_row_alone
- TRACK-19: `test/tracker_test.rb` test_run_polls_and_yields_each_summary_between_sleeps
- TRACK-20: unproven
- TRACK-21: unproven
- TRACK-22: `test/tracker_test.rb` test_a_reported_row_with_pending_checks_is_watched_until_they_pass, test_a_reported_row_without_check_runs_yet_is_watched_until_they_appear, test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched, test_a_pull_request_closed_without_merging_stops_being_watched
- TRACK-23: `test/tracker_test.rb` test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched, test_a_pull_request_closed_without_merging_stops_being_watched; `test/github_client_test.rb` test_pull_request_status_is_success_when_every_run_completed_and_passed, test_pull_request_status_reads_every_page_of_check_runs, test_pull_request_status_stops_paging_at_an_empty_page_when_the_count_is_off, test_pull_request_status_is_failure_when_a_completed_run_failed, test_pull_request_status_is_pending_without_a_time_when_a_run_has_not_completed, test_pull_request_status_is_none_when_there_are_no_check_runs_and_reads_the_merge
- TRACK-24: `test/tracker_test.rb` test_reported_session_with_pull_request_and_output_is_recorded_and_notified_once, test_a_reported_row_without_check_runs_yet_is_watched_until_they_appear, test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched; `test/github_client_test.rb` test_pull_request_status_is_success_when_every_run_completed_and_passed
- TRACK-25: `test/tracker_test.rb` test_pr_checks_at_is_unchanged_when_checks_are_still_success
- TRACK-26: `test/tracker_test.rb` test_a_reported_row_without_check_runs_yet_is_watched_until_they_appear
- TRACK-27: `test/tracker_test.rb` test_a_github_error_while_checking_the_pull_request_is_counted_and_leaves_the_row_alone, test_a_github_error_during_an_open_poll_still_notifies_and_closes_the_session, test_a_pull_request_url_off_github_is_an_error_not_a_crash
- TRACK-28: `test/tracker_test.rb` test_red_checks_send_the_failed_runs_to_the_session_once_per_commit, test_red_checks_seen_during_an_open_poll_message_the_session_before_it_settles; `test/github_client_test.rb` test_failed_check_runs_keeps_only_the_failure_conclusions_with_name_url_and_summary, test_failed_check_runs_falls_back_to_the_output_text_and_keeps_only_the_first_forty_lines, test_failed_check_runs_is_empty_when_nothing_failed_or_the_output_is_absent, test_pull_request_status_reads_every_page_of_check_runs, test_pull_request_status_reads_the_head_branch; `test/repair_prompt_test.rb` test_renders_the_flask_example_with_both_escape_import_errors, test_lists_a_job_without_output_as_just_its_name_and_url
- TRACK-29: `test/tracker_test.rb` test_red_checks_send_the_failed_runs_to_the_session_once_per_commit
- TRACK-30: `test/tracker_test.rb` test_a_new_red_commit_gets_a_second_repair_and_the_third_is_left_for_a_human
- TRACK-31: `test/tracker_test.rb` test_a_failed_repair_message_is_counted_and_retried_next_round
- TRACK-32: `test/tracker_test.rb` test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched, test_a_pull_request_closed_without_merging_stops_being_watched
- TRACK-33: `test/tracker_test.rb` test_red_checks_wait_for_a_working_session_to_stop_before_it_is_asked_to_repair

</details>
