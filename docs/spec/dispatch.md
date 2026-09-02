# Dispatch

A finding becomes work for Devin exactly once. The dispatcher renders the
remediation prompt, asks Devin for a session, and records it, refusing to
start a second session for a finding that already has one, a fix branch, or
a fix pull request.

## Deciding whether to dispatch

**DISP-01** IF the finding has no fix version, THEN THE dispatcher SHALL
return `not_fixable` and call neither GitHub nor Devin.
Proof: test/dispatcher_test.rb test_finding_without_a_fix_version_is_not_fixable

**DISP-02** IF no findings row has the issue number, THEN THE dispatcher
SHALL return `not_found` and call neither GitHub nor Devin.
Proof: test/dispatcher_test.rb test_unknown_issue_is_not_found

**DISP-03** IF the target repository has an open pull request from branch
`fix/<package>-sla-<issue_number>`, or that branch exists, THEN THE
dispatcher SHALL return `already_dispatched`, print why, and create no
session.
Proof: test/dispatcher_test.rb test_open_fix_pull_request_is_already_dispatched_without_a_post,
test_existing_fix_branch_is_already_dispatched_without_a_post

**DISP-04** IF GitHub answers the branch or pull-request check with an error
other than "not found", THEN THE dispatcher SHALL fail with that error and
create no session.
Proof: test/dispatcher_test.rb test_github_errors_other_than_404_propagate_without_a_post

**DISP-05** IF the findings row lacks the issue title or URL, THEN THE
dispatcher SHALL fetch them from GitHub and store them on the row before
rendering the prompt; when both are present it SHALL not ask GitHub.
Proof: test/dispatcher_test.rb test_missing_issue_details_are_fetched_from_github_and_stored,
test_present_issue_details_are_not_fetched

## Creating the session

**DISP-06** WHEN dispatching, THE dispatcher SHALL create one Devin session
with the rendered prompt, the issue title as the session title, the target
repository as its only repository, tags `sla-remediation` and
`issue-<issue_number>`, the remediation result schema as its structured
output schema, an ACU limit of 3, and `resumable` false.
Proof: test/dispatcher_test.rb test_dispatch_creates_one_session_and_records_it;
test/devin_client_test.rb test_create_session_posts_the_recorded_request_body

**DISP-07** WHEN the session is created, THE dispatcher SHALL record one
sessions row for the finding holding the Devin session id, status, status
detail, start time, and last-polled time, print the session URL, and return
`dispatched`.
Proof: test/dispatcher_test.rb test_dispatch_creates_one_session_and_records_it

**DISP-08** THE dispatcher SHALL hold at most one sessions row per finding;
dispatching a finding that has one SHALL return `already_dispatched` and
not call Devin.
Proof: test/dispatcher_test.rb test_two_dispatches_of_the_same_finding_post_once

**DISP-09** THE dispatcher SHALL reserve the sessions row before calling
Devin, so that two dispatches racing for one finding result in one Devin
call; the loser SHALL return `already_dispatched`.
Proof: test/dispatcher_test.rb test_the_sessions_row_is_reserved_before_devin_is_called,
test_losing_the_reservation_race_is_already_dispatched_without_a_post

**DISP-10** IF Devin refuses or fails to create the session, THEN THE
dispatcher SHALL remove the reservation, leave the findings row in place,
and fail with the Devin error, so a later dispatch can succeed.
Proof: test/dispatcher_test.rb test_a_failed_devin_call_releases_the_reservation_and_raises

## Preview

**DISP-11** WHEN asked to preview, THE dispatcher SHALL print the rendered
prompt and the session request as JSON, create no session, write no
sessions row, and still store missing issue details as in DISP-05.
Proof: test/dispatcher_test.rb test_preview_prints_the_prompt_and_payload_without_posting,
test_preview_fetches_missing_issue_details_and_stores_them

**DISP-12** WHEN asked to preview an unfixable or unknown finding, THE
dispatcher SHALL return `not_fixable` or `not_found` and print nothing.
Proof: test/dispatcher_test.rb test_preview_of_an_unfixable_or_unknown_issue

## The prompt and the schema

**DISP-13** THE rendered prompt SHALL name the target repository, the issue
number, title, and URL, the package, pinned version, advisories, fix
version, and severity, the due date in UTC as `YYYY-MM-DD HH:MM UTC`, the
branch `fix/<package>-sla-<issue_number>`, and instruct the pull request to
say `Fixes #<issue_number>`; it SHALL contain no unrendered template tags.
Proof: test/remediation_prompt_test.rb test_render_names_the_finding_and_the_rules,
test_render_formats_due_at_in_utc, test_render_leaves_no_erb_tags

**DISP-14** THE structured output schema SHALL be valid JSON Schema
draft-07, accept a complete remediation result, reject an unknown
`lockfile_route`, a missing `pr_url`, or an incomplete `verification`, and
be smaller than 64 KB.
Proof: test/remediation_prompt_test.rb test_schema_is_valid_draft_07_and_accepts_a_remediation_result,
test_schema_fits_the_session_request_limit

## Automatic dispatch from the webhook

**DISP-15** WHILE `SLA_AUTO_DISPATCH` is `true`, WHEN the receiver starts a
finding, THE service SHALL dispatch it in the same delivery and log the
dispatch result on the delivery line; a duplicate delivery SHALL not call
Devin again.
Proof: test/webhook_test.rb test_opened_with_auto_dispatch_starts_one_session

**DISP-16** WHILE `SLA_AUTO_DISPATCH` is not `true`, THE service SHALL only
record findings and log `dispatch=off`.
Proof: test/webhook_test.rb test_opened_without_auto_dispatch_records_only_the_finding

**DISP-17** IF an automatic dispatch fails, THEN THE service SHALL keep the
findings row, create no session, log the error on the delivery line, and
not retry on its own.
Proof: test/webhook_test.rb test_auto_dispatch_failure_keeps_the_finding_and_logs_the_error

**DISP-18** THE automatic dispatch SHALL apply DISP-01 and DISP-03 the same
way as a manual one, logging `not_fixable` or `already_dispatched`.
Proof: test/webhook_test.rb test_auto_dispatch_of_an_unfixable_finding_creates_nothing,
test_auto_dispatch_skips_a_finding_whose_fix_branch_exists

## Devin client

**DISP-19** THE Devin client SHALL treat any non-2xx response as an error
carrying the HTTP status and parsed body.
Proof: test/devin_client_test.rb test_not_found_raises_devin_api_error

**DISP-20** THE Devin client SHALL list the organisation's repositories from
the `v3beta1` repositories endpoint.
Proof: test/devin_client_test.rb test_list_repositories_uses_v3beta1_and_maps_structs

## Command

**DISP-21** `bin/dispatch <issue_number>` SHALL dispatch one finding and
exit 0 for `dispatched` or `already_dispatched` and 1 otherwise;
`--dry-run` SHALL preview instead and exit 0.
Proof: unproven

**DISP-22** IF `DEVIN_SERVICE_API_KEY_V3`, `DEVIN_ORG_ID`, or `SLA_REPO` is
unset, THEN `bin/dispatch` SHALL name the missing variables and exit 1
without dispatching.
Proof: unproven

## Unproven

DISP-21, DISP-22. The command-line entry point has no tests.

## Not specified

- The prose of the prompt beyond the facts DISP-13 names.
- The wording of printed lines.
- Message sending and reading on a session; the client supports both but no
  slice uses them.
- What Devin does with the session; the service's promise ends at creating
  it.
