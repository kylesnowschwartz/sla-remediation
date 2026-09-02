# Receive

GitHub posts an `issues` event to `POST /webhooks/github` for every change to
an issue in the target repository. The receiver keeps only the events that
create or close a labelled finding, checks that each came from GitHub, and
writes one findings row with a due date computed from the policy.

## Authentication

**RECV-01** IF a delivery's `X-Hub-Signature-256` header is missing, or does
not equal the HMAC-SHA256 of the raw body under `SLA_WEBHOOK_SECRET`, THEN
THE receiver SHALL respond 401 before parsing the body and write nothing.
Proof: test/webhook_test.rb test_missing_signature_is_rejected, test_tampered_body_is_rejected

**RECV-02** THE receiver SHALL compare signatures in constant time and accept
GitHub's `sha256=<hex>` format.
Proof: test/webhook_test.rb test_signature_helper_matches_github_format

**RECV-03** WHEN a signed `ping` event arrives, THE receiver SHALL respond
200 `{"ok":true}` whatever the body holds.
Proof: test/webhook_test.rb test_ping_returns_ok

**RECV-04** IF a signed body is not valid JSON, THEN THE receiver SHALL
respond 400.
Proof: test/webhook_test.rb test_invalid_json_is_a_bad_request

## Selecting events

**RECV-05** THE receiver SHALL act only on `issues` events whose action is
`opened` with the `sla-remediation` label already on the issue, `labeled`
with `sla-remediation` as the label added, or `closed`; every other event or
action SHALL get 204 and write nothing.
Proof: test/webhook_test.rb test_other_events_are_ignored, test_unrelated_action_is_ignored,
test_opened_without_the_label_is_ignored, test_labeled_with_another_label_is_ignored

## Recording a finding

**RECV-06** WHEN an `opened` or `labeled` event selects an issue with no
findings row, THE receiver SHALL insert one row holding the issue number,
title, and URL, the fields of the issue's finding block (`package`,
`pinned`, `fix_version`, `severity`, `source`, `advisories`, `ecosystem`),
`opened_at` from the issue's creation time, and `due_at` from the policy for
the finding's severity, then respond 200 `{"result":"started"}`.
Proof: test/webhook_test.rb test_opened_then_labeled_records_one_finding,
test_ecosystem_from_the_finding_block_is_stored

**RECV-07** THE receiver SHALL hold at most one findings row per issue
number; a second selecting event for the same issue SHALL respond 200
`{"result":"duplicate"}` and change nothing.
Proof: test/webhook_test.rb test_opened_then_labeled_records_one_finding

**RECV-08** IF the issue body has no finding block, THEN THE receiver SHALL
respond 422 with an error saying so and write nothing.
Proof: test/webhook_test.rb test_labeled_issue_without_a_finding_block_is_unprocessable

**RECV-09** IF the finding block's severity is not one the policy knows,
THEN THE receiver SHALL respond 422 naming the severity and write nothing.
Proof: test/webhook_test.rb test_labeled_issue_with_unknown_severity_is_unprocessable

**RECV-10** IF the finding block omits `ecosystem`, THEN THE stored row
SHALL carry `pypi`.
Proof: unproven (the default is tested at the parser, SCAN-17, not on the stored row)

## Closing a finding

**RECV-11** WHEN a `closed` event names an issue with a findings row, THE
receiver SHALL set the row's `closed_at` from the issue's closing time and
respond 200 `{"result":"remediated"}`.
Proof: test/webhook_test.rb test_closed_marks_the_finding_remediated

**RECV-12** IF a `closed` event names an issue with no findings row, THEN THE
receiver SHALL respond 204 and write nothing.
Proof: test/webhook_test.rb test_closed_without_a_finding_is_ignored

## Logging and health

**RECV-13** THE receiver SHALL log one line per processed delivery giving
the event, action, issue number, and result, plus the dispatch result when
auto-dispatch is on (see DISP-14 to DISP-17).
Proof: test/webhook_test.rb test_opened_without_auto_dispatch_records_only_the_finding

**RECV-14** THE service SHALL answer `GET /healthz` with 200 and the JSON
body `{"ok":true}`.
Proof: test/app_test.rb test_healthz_returns_ok

## Unproven

RECV-10.

## Not specified

- The exact wording of error bodies and log lines.
- Behaviour when the policy file cannot be fetched at request time.
- Any event source other than GitHub issues; Dependabot alerts and other
  feeds are not received.
