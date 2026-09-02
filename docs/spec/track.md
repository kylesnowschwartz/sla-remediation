# Track

Devin sessions never report back on their own, so the tracker asks. It polls
every open session, records what it sees, decides when a session is finished
and whether it delivered, and tells the issue about the pull request once.

## What is polled

**TRACK-01** THE tracker SHALL poll every sessions row that has a Devin
session id and no outcome, in the order the rows were created.
Proof: test/tracker_test.rb test_working_session_stays_open,
test_rows_without_a_devin_session_id_are_skipped

**TRACK-02** WHEN a row has an outcome, THE tracker SHALL never fetch its
session again.
Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once,
test_suspended_session_without_report_or_pull_request_is_stalled

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
notifier that posts nothing.
Proof: test/notifier_test.rb test_null_posts_nothing (the wiring in `bin/track` is unproven)

## The polling round

**TRACK-17** WHEN one session's poll fails, THE tracker SHALL log the error,
count it, and continue with the remaining sessions in the same round.
Proof: test/tracker_test.rb test_an_error_for_one_session_does_not_stop_the_others

**TRACK-18** EACH round SHALL yield a summary counting sessions polled,
settled, stalled, notified, and errored.
Proof: test/tracker_test.rb test_an_error_for_one_session_does_not_stop_the_others

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

TRACK-20, TRACK-21, and the notifier wiring in TRACK-16. The command-line
entry point has no tests.

## Not specified

- The wording of log lines.
- Whether a stored valid structured output is ever replaced by a later one;
  the tracker keeps the first, but no test holds it to that.
- Resuming, terminating, or archiving sessions; the tracker only reads.
