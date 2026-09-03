# Receive

GitHub posts `issues` events to `POST /webhooks/github`; the receiver checks each came from GitHub, keeps the ones that open or close a labelled finding, and writes one findings row with a due date from the policy.

## Authentication

- **RECV-01** Checks `X-Hub-Signature-256` before anything else:
  - must equal HMAC-SHA256 of the raw body under `SLA_WEBHOOK_SECRET`
  - missing or wrong → 401 before the body is parsed, nothing written
- **RECV-02** Compares signatures in constant time, in GitHub's `sha256=<hex>` format.
- **RECV-03** A signed `ping` → 200 `{"ok":true}`, whatever the body holds.
- **RECV-04** A signed body that is not valid JSON → 400.

## Recording a finding

- **RECV-05** Acts only on these `issues` actions; any other event or action → 204, nothing written:
  - `opened` with `sla-remediation` already on the issue
  - `labeled` where the label added is `sla-remediation`
  - `closed`
- **RECV-06** `opened`/`labeled` on an issue with no row inserts one → 200 `{"result":"started"}`:
  - issue number, title, URL
  - the finding block's `package`, `pinned`, `fix_version`, `severity`, `source`, `advisories`, `ecosystem`
  - `opened_at` from the issue's creation time, `due_at` from the policy for that severity
- **RECV-07** One row per issue number at most; a repeat event → 200 `{"result":"duplicate"}`, no change.
- **RECV-08** Issue body with no finding block → 422 saying so, nothing written.
- **RECV-09** Severity the policy does not know → 422 naming the severity, nothing written.
- **RECV-10** A finding block that omits `ecosystem` stores `pypi`.
- **RECV-11** `closed` with a row → `closed_at` from the closing time, 200 `{"result":"remediated"}`.
- **RECV-12** `closed` with no row → 204, nothing written.

## Logging and health

- **RECV-13** One log line per processed delivery:
  - event, action, issue number, result
  - the dispatch result too, when auto-dispatch is on (DISP-14 to DISP-17)
- **RECV-14** `GET /healthz` → 200 `{"ok":true}`.

## Not specified

- The exact wording of error bodies and log lines.
- Behaviour when the policy file cannot be fetched at request time.
- Any event source other than GitHub issues; Dependabot and other feeds are not received.

<details><summary>Proofs</summary>

- RECV-01: `test/webhook_test.rb` test_missing_signature_is_rejected, test_tampered_body_is_rejected
- RECV-02: `test/webhook_test.rb` test_signature_helper_matches_github_format
- RECV-03: `test/webhook_test.rb` test_ping_returns_ok
- RECV-04: `test/webhook_test.rb` test_invalid_json_is_a_bad_request
- RECV-05: `test/webhook_test.rb` test_other_events_are_ignored, test_unrelated_action_is_ignored, test_opened_without_the_label_is_ignored, test_labeled_with_another_label_is_ignored
- RECV-06: `test/webhook_test.rb` test_opened_then_labeled_records_one_finding, test_ecosystem_from_the_finding_block_is_stored
- RECV-07: `test/webhook_test.rb` test_opened_then_labeled_records_one_finding
- RECV-08: `test/webhook_test.rb` test_labeled_issue_without_a_finding_block_is_unprocessable
- RECV-09: `test/webhook_test.rb` test_labeled_issue_with_unknown_severity_is_unprocessable
- RECV-10: unproven (the default is tested at the parser, SCAN-17, not on the stored row)
- RECV-11: `test/webhook_test.rb` test_closed_marks_the_finding_remediated
- RECV-12: `test/webhook_test.rb` test_closed_without_a_finding_is_ignored
- RECV-13: `test/webhook_test.rb` test_opened_without_auto_dispatch_records_only_the_finding
- RECV-14: `test/app_test.rb` test_healthz_returns_ok

</details>
