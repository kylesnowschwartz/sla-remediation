# Track

Devin sessions never report back on their own, so the tracker asks. It polls
every open session, records what it sees, decides when a session is finished
and whether it delivered, and tells the issue about the pull request once.
It then follows the pull request on GitHub until it is merged, closed, or
green, so the status page can judge a finding fixed by the pull request
passing rather than by the session ending.

## What is polled

**TRACK-01** THE tracker SHALL poll every sessions row that has a Devin
session id and no outcome, in the order the rows were created.
Proof: test/tracker_test.rb test_working_session_stays_open,
test_rows_without_a_devin_session_id_are_skipped

**TRACK-02** WHEN a row has an outcome, THE tracker SHALL never fetch its
session again (its pull request may still be followed; see TRACK-22).
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once,
test_suspended_session_without_report_or_pull_request_is_stalled,
test_a_settled_row_with_pending_checks_is_watched_until_they_pass

## What is recorded

**TRACK-03** WHEN a session is fetched, THE tracker SHALL record its status,
status detail, ACUs consumed, and the poll time, and the URL and state of
its first pull request when it has one.
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once,
test_working_session_stays_open

**TRACK-04** WHEN a session carries structured output that matches the
remediation result schema, THE tracker SHALL store it as JSON text in
`structured_output`.
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once

**TRACK-05** IF the structured output does not match the schema, THEN THE
tracker SHALL store it as JSON text in `structured_output_invalid`, log a
warning naming the first problem, and discard nothing.
Proof: test/tracker_test.rb test_output_of_another_shape_is_kept_as_invalid_with_a_warning

**TRACK-06** THE tracker SHALL read the API's structured output as an
object, or as a JSON string to be parsed, and treat the string `"null"` or
an absent value as no output.
Proof: test/devin_client_test.rb test_structured_output_object_stays_a_hash,
test_structured_output_json_string_is_parsed, test_structured_output_string_null_becomes_nil

**TRACK-07** WHEN a session's status or status detail differs from the last
recorded value, THE tracker SHALL log the change once, naming the issue and
session.
Proof: test/tracker_test.rb test_a_status_change_is_logged_once

## Deciding the outcome

**TRACK-08** THE tracker SHALL judge a session stopped when its status is
`exit` or `error`, or its status detail is `waiting_for_user`, `finished`,
or `inactivity`; a running session with no such detail is not stopped.
Proof: test/devin_client_test.rb test_running_session_is_not_stopped,
test_waiting_for_user_with_output_is_settled, test_suspended_with_pr_is_stopped_and_reported

**TRACK-09** THE tracker SHALL judge a session reported when it has
structured output or at least one pull request.
Proof: test/devin_client_test.rb test_waiting_for_user_with_output_is_settled,
test_suspended_with_pr_is_stopped_and_reported

**TRACK-10** WHEN a session is stopped and reported, THE tracker SHALL set
the row's outcome to `settled` and its finish time to the session's last
update time.
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once,
test_suspended_session_with_pull_request_is_settled_and_notified_once,
test_output_of_another_shape_is_kept_as_invalid_with_a_warning

**TRACK-11** WHEN a session is stopped but not reported, THE tracker SHALL set
the outcome to `stalled` and log a warning naming the issue, session, and
status.
Proof: test/tracker_test.rb test_suspended_session_without_report_or_pull_request_is_stalled;
test/devin_client_test.rb test_stopped_without_output_or_pr_is_stalled

**TRACK-12** WHILE a session is not stopped, THE tracker SHALL leave the row
open with no outcome and no finish time.
Proof: test/tracker_test.rb test_working_session_stays_open

## Telling the issue

**TRACK-13** WHEN a row first gains a pull request URL, THE tracker SHALL
record the time in `pr_notified_at` and then ask the notifier to announce
the pull request, once.
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once,
test_suspended_session_with_pull_request_is_settled_and_notified_once,
test_a_failed_notification_clears_the_timestamp_and_leaves_the_row_open

**TRACK-14** IF the announcement fails, THEN THE tracker SHALL clear
`pr_notified_at`, leave the row open, log the error, and count it as an
error, so the next poll tries again.
Proof: test/tracker_test.rb test_a_failed_notification_clears_the_timestamp_and_leaves_the_row_open

**TRACK-15** THE issue-comment notifier SHALL post one comment on the
finding's issue giving the pull request URL, the Devin session URL, the due
date as `YYYY-MM-DD HH:MM UTC`, and whether now is inside or past the SLA
window.
Proof: test/notifier_test.rb test_issue_comment_posts_the_links_and_inside_the_window,
test_issue_comment_says_past_the_window_after_the_due_date

**TRACK-16** WHILE `SLA_GITHUB_TOKEN` is unset, THE tracker SHALL use a
notifier that posts nothing and SHALL not ask GitHub about pull requests at
all, so that it never polls anonymously.
Proof: test/notifier_test.rb test_null_posts_nothing;
test/tracker_test.rb test_without_a_github_client_pull_requests_are_never_looked_at
(the wiring in `bin/track` is unproven)

## Following the pull request

**TRACK-22** THE tracker SHALL ask GitHub about a row's pull request on
every poll of an open session that has one, and on every round for a
closed row whose pull request is not yet merged or closed and whose checks
are not yet `success` (unobserved, `none`, `pending`, or `failure`). Rows
whose pull request is merged, closed, or green SHALL not be asked about
again.
Proof: test/tracker_test.rb test_a_settled_row_with_pending_checks_is_watched_until_they_pass,
test_a_settled_row_without_check_runs_yet_is_watched_until_they_appear,
test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched,
test_a_pull_request_closed_without_merging_stops_being_watched

**TRACK-23** WHEN GitHub answers, THE tracker SHALL record the pull
request's state as `merged`, `closed`, or `open` from GitHub (replacing what
the session reported), the aggregate check state over every check run on
the head commit, read page by page until GitHub's `total_count` is reached
or a page comes back empty (`success` when every completed run passed, was
neutral, or was skipped; `failure` when any run failed; `pending` while any
run is unfinished; `none` when there are no runs), and the merge time once.
Proof: test/tracker_test.rb test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched,
test_a_pull_request_closed_without_merging_stops_being_watched;
test/github_client_test.rb test_pull_request_status_is_success_when_every_run_completed_and_passed,
test_pull_request_status_reads_every_page_of_check_runs,
test_pull_request_status_stops_paging_at_an_empty_page_when_the_count_is_off,
test_pull_request_status_is_failure_when_a_completed_run_failed,
test_pull_request_status_is_pending_without_a_time_when_a_run_has_not_completed,
test_pull_request_status_is_none_when_there_are_no_check_runs_and_reads_the_merge

**TRACK-24** THE times recorded for a merge and for completed checks SHALL
be GitHub's own (`merged_at`, and the latest `completed_at` among the check
runs), not the time the tracker noticed them, so an outage does not turn a
timely fix late. WHILE checks are `pending` or `none`, the check time SHALL
be when the tracker saw them.
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once,
test_a_settled_row_without_check_runs_yet_is_watched_until_they_appear,
test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched;
test/github_client_test.rb test_pull_request_status_is_success_when_every_run_completed_and_passed

**TRACK-25** WHILE the check state is unchanged, THE tracker SHALL leave the
check time alone.
Proof: test/tracker_test.rb test_pr_checks_at_is_unchanged_when_checks_are_still_success

**TRACK-26** WHEN the checks turn `failure` from any other state, THE
tracker SHALL log it once, naming the issue and pull request.
Proof: test/tracker_test.rb test_a_settled_row_without_check_runs_yet_is_watched_until_they_appear

**TRACK-27** IF asking GitHub fails, or the pull request URL is not a GitHub
pull request, THEN THE tracker SHALL log the error, count it, leave the
row's pull request columns as they were, and still announce the pull
request and decide the session's outcome in the same poll.
Proof: test/tracker_test.rb test_a_github_error_while_checking_the_pull_request_is_counted_and_leaves_the_row_alone,
test_a_github_error_during_an_open_poll_still_notifies_and_closes_the_session,
test_a_pull_request_url_off_github_is_an_error_not_a_crash

## Sending red checks back to the session

**TRACK-28** WHEN a row's pull request is `open` and its checks are
`failure` at a head sha that differs from the row's `ci_repair_sha`, THE
tracker SHALL take that sha's failed check runs from the check runs it
read for TRACK-23 (each run's name, `details_url`, and the first 40 lines
of `output.summary`, or of `output.text` when there is no summary;
conclusions `failure`, `timed_out`, `cancelled`, `action_required`; the
endpoint is not read a second time and job logs are not downloaded),
render `prompts/repair_ci.md.erb` with the pull request URL, branch, sha,
and those runs, and send it as a message to the Devin session that opened
the pull request. It SHALL NOT create a new session.
Proof: test/tracker_test.rb test_red_checks_send_the_failed_runs_to_the_session_once_per_commit,
test_red_checks_seen_during_an_open_poll_message_the_session_before_it_settles;
test/github_client_test.rb test_failed_check_runs_keeps_only_the_failure_conclusions_with_name_url_and_summary,
test_failed_check_runs_falls_back_to_the_output_text_and_keeps_only_the_first_forty_lines,
test_failed_check_runs_is_empty_when_nothing_failed_or_the_output_is_absent,
test_pull_request_status_reads_every_page_of_check_runs,
test_pull_request_status_reads_the_head_branch;
test/repair_prompt_test.rb test_renders_the_flask_example_with_both_escape_import_errors,
test_lists_a_job_without_output_as_just_its_name_and_url

**TRACK-29** WHEN the message has been sent, THE tracker SHALL record the
sha as `ci_repair_sha` and increment `ci_repairs`; WHILE `ci_repair_sha`
equals the observed head sha, THE tracker SHALL NOT send another message,
however many rounds the checks stay red.
Proof: test/tracker_test.rb test_red_checks_send_the_failed_runs_to_the_session_once_per_commit

**TRACK-30** WHEN the checks are red at a new head sha and `ci_repairs` is
below `MAX_CI_REPAIRS` (2), THE tracker SHALL send another message; WHEN
`ci_repairs` has reached the cap, THE tracker SHALL log once per red sha
that the pull request is left for a human, send nothing, and leave
`ci_repair_sha` and `ci_repairs` as they were.
Proof: test/tracker_test.rb test_a_new_red_commit_gets_a_second_repair_and_the_third_is_left_for_a_human

**TRACK-31** IF sending the message fails, THEN THE tracker SHALL count the
error, keep the check state it recorded, leave `ci_repair_sha` and
`ci_repairs` unchanged, and try again on the next round.
Proof: test/tracker_test.rb test_a_failed_repair_message_is_counted_and_retried_next_round

**TRACK-32** THE tracker SHALL NOT message the session about a pull request
that is merged or closed, whatever its checks say.
Proof: test/tracker_test.rb test_a_merged_pull_request_records_the_merge_time_and_state_and_stops_being_watched,
test_a_pull_request_closed_without_merging_stops_being_watched

**TRACK-33** WHILE the session is `running` with a status detail other than
`waiting_for_user`, `finished`, or `inactivity` (it is still working), THE
tracker SHALL record the red checks but send no repair message and spend no
repair, logging once per red sha that the repair waits; WHEN the session
stops, THE tracker SHALL send the message for that sha on the next round
as TRACK-28 says.
Proof: test/tracker_test.rb test_red_checks_wait_for_a_working_session_to_stop_before_it_is_asked_to_repair

## The polling round

**TRACK-17** WHEN one session's poll fails, THE tracker SHALL log the error,
count it, and continue with the remaining sessions in the same round.
Proof: test/tracker_test.rb test_an_error_for_one_session_does_not_stop_the_others

**TRACK-18** EACH round SHALL yield a summary counting sessions polled,
settled, stalled, notified, and errors (from session polls and pull
request checks alike).
Proof: test/tracker_test.rb test_an_error_for_one_session_does_not_stop_the_others,
test_a_github_error_while_checking_the_pull_request_is_counted_and_leaves_the_row_alone

**TRACK-19** WHEN run as a loop, THE tracker SHALL poll, report the round,
sleep the interval, and repeat until stopped.
Proof: test/tracker_test.rb test_run_polls_and_yields_each_summary_between_sleeps

## Command

**TRACK-20** `bin/track` SHALL run one round and print the summary as
`polled= settled= stalled= notified= errors=`; `bin/track --loop` SHALL
repeat every 15 seconds until interrupted.
Proof: unproven

**TRACK-21** IF `DEVIN_SERVICE_API_KEY_V3` or `DEVIN_ORG_ID` is unset, THEN
`bin/track` SHALL name the missing variables and exit 1 without polling.
Proof: unproven

## Unproven

TRACK-20, TRACK-21, and the notifier and GitHub wiring in TRACK-16. The
command-line entry point has no tests.

## Not specified

- The wording of log lines.
- Legacy commit statuses; only the Checks API is read.
- Whether a pull request that turns green, then red again, is judged by
  its earlier green; the tracker records the latest state, and the status
  page spec decides what that means.
- Whether a stored valid structured output is ever replaced by a later one;
  the tracker keeps the first, but no test holds it to that.
- Resuming, terminating, or archiving sessions; the tracker's only write to
  Devin is the repair message of TRACK-28, which relies on the session being
  `resumable` (DISP-06).
- The wording of the repair message beyond what TRACK-28 names; the
  template is the artifact.
