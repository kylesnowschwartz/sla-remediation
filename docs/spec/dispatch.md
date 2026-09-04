# Dispatch

A finding becomes work for Devin exactly once: never a second session when a session, a fix branch, or a fix pull request already exists.

## Deciding whether to dispatch

- **DISP-01** No fix version → `not_fixable`; no GitHub or Devin call.
- **DISP-02** No findings row for the issue number → `not_found`; no GitHub or Devin call.
- **DISP-03** Branch `fix/<package>-sla-<issue_number>` or an open PR from it → `already_dispatched`, why printed.
- **DISP-04** A branch or PR check error other than not-found → fail with it, no session.
- **DISP-05** Missing issue title/URL fetched from GitHub and stored before rendering; present ones aren't.

## Creating the session

- **DISP-06** Dispatch creates exactly one Devin session:
  - rendered prompt, issue title as session title, target repository as its only repository
  - the playbook `DEVIN_PLAYBOOK_ID` names, which holds the remediation procedure
  - tags `sla-remediation` and `issue-<issue_number>`
  - remediation result schema as structured output, ACU limit 3, `resumable` true (so the tracker can message it later, TRACK-28)
- **DISP-07** Writes a sessions row (id, status, detail, start, last poll), prints URL, returns `dispatched`.
- **DISP-08** At most one sessions row per finding; a second dispatch → `already_dispatched`, no Devin call.
- **DISP-09** Row reserved before the Devin call: a race makes one call, the loser `already_dispatched`.
- **DISP-10** Devin failing → reservation released, findings row kept, error raised; a retry can succeed.
- **DISP-11** Preview prints prompt and request JSON, writes no session or row, still stores DISP-05 details.
- **DISP-12** Preview of an unfixable or unknown finding → `not_fixable`/`not_found`, nothing printed.

## The prompt and the schema

- **DISP-13** The rendered prompt names the whole finding, tells the session to follow the attached playbook, and leaves no unrendered template tags:
  - target repository, issue number, title, URL
  - package, pinned version, advisories, fix version, severity
  - due date in UTC as `YYYY-MM-DD HH:MM UTC`, branch `fix/<package>-sla-<issue_number>`
  - none of the procedure: the lockfile route, the pip-audit check, and the PR rules are in the playbook
- **DISP-14** The structured output schema is valid JSON Schema draft-07 and smaller than 64 KB:
  - accepts a complete remediation result
  - rejects an unknown `lockfile_route`, a missing `pr_url`, or an incomplete `verification`
- **DISP-23** A fix version in a new major series switches the prompt's one-line verdict to the major-version case:
  - the prompt says the fix crosses a major version, that the minimal source and test changes the upgrade breaks are permitted, and that the structured output must include `breaking_changes` and `tests_run`
  - a same-major fix version says to change nothing but the pin, byte-identical to the baseline prompt
  - the playbook carries both procedures: the lowest release of the new major series, the affected tests run with `pytest` (or CI relied on, never the change skipped), no dependency changes beyond what the new major strictly requires
- **DISP-24** The schema accepts optional `breaking_changes` (`{file, reason}`) and `tests_run` (strings).
- **DISP-25** The playbook body keeps every rule of the procedure: never a PR against `apache/superset`, the `uv pip compile` recompile with the direct-edit fall-back, `pip-audit --disable-pip --no-deps` on the file without `-e ./superset-core`, `Fixes #<issue number>`, no unrelated changes, no full test suite.

## Automatic dispatch from the webhook

- **DISP-15** While `SLA_AUTO_DISPATCH` is `true`, a finding the receiver starts is dispatched:
  - in the same delivery, with the result logged on the delivery line
  - a duplicate delivery does not call Devin again
- **DISP-16** While `SLA_AUTO_DISPATCH` is not `true`, findings are recorded only, logged `dispatch=off`.
- **DISP-17** Failed automatic dispatch, including an unset `DEVIN_PLAYBOOK_ID`: findings row kept, no session, error logged, no retry.
- **DISP-18** DISP-01 and DISP-03 apply to automatic dispatch, logged `not_fixable` or `already_dispatched`.

## Devin client and command

- **DISP-19** Any non-2xx response is an error carrying the HTTP status and the parsed body.
- **DISP-20** Organisation repositories are listed from the `v3beta1` repositories endpoint.
- **DISP-21** `bin/dispatch <issue_number>` dispatches one finding:
  - exit 0 for `dispatched` or `already_dispatched`, 1 otherwise
  - `--dry-run` previews instead and exits 0
- **DISP-22** `DEVIN_SERVICE_API_KEY_V3`, `DEVIN_ORG_ID`, `DEVIN_PLAYBOOK_ID`, or `SLA_REPO` unset → named, exit 1, no dispatch.
- **DISP-26** `bin/playbook-sync` creates the organization playbook (title, `!remediate-pip` macro, body, schema) when absent, updates it when they differ, and prints `DEVIN_PLAYBOOK_ID=<id>`; a second run changes nothing.

## Not specified

- The prose of the prompt beyond the facts DISP-13 names.
- The wording of printed lines.
- Reading messages on a session; the client supports it, no slice uses it. Sending is the tracker's (TRACK-28).
- What Devin does with the session; the promise ends at creating it.

<details><summary>Proofs</summary>

- DISP-01: `test/dispatcher_test.rb` test_finding_without_a_fix_version_is_not_fixable
- DISP-02: `test/dispatcher_test.rb` test_unknown_issue_is_not_found
- DISP-03: `test/dispatcher_test.rb` test_open_fix_pull_request_is_already_dispatched_without_a_post, test_existing_fix_branch_is_already_dispatched_without_a_post
- DISP-04: `test/dispatcher_test.rb` test_github_errors_other_than_404_propagate_without_a_post
- DISP-05: `test/dispatcher_test.rb` test_missing_issue_details_are_fetched_from_github_and_stored, test_present_issue_details_are_not_fetched
- DISP-06: `test/dispatcher_test.rb` test_dispatch_creates_one_session_and_records_it; `test/devin_client_test.rb` test_create_session_posts_the_recorded_request_body
- DISP-07: `test/dispatcher_test.rb` test_dispatch_creates_one_session_and_records_it
- DISP-08: `test/dispatcher_test.rb` test_two_dispatches_of_the_same_finding_post_once
- DISP-09: `test/dispatcher_test.rb` test_the_sessions_row_is_reserved_before_devin_is_called, test_losing_the_reservation_race_is_already_dispatched_without_a_post
- DISP-10: `test/dispatcher_test.rb` test_a_failed_devin_call_releases_the_reservation_and_raises
- DISP-11: `test/dispatcher_test.rb` test_preview_prints_the_prompt_and_payload_without_posting, test_preview_fetches_missing_issue_details_and_stores_them
- DISP-12: `test/dispatcher_test.rb` test_preview_of_an_unfixable_or_unknown_issue
- DISP-13: `test/remediation_prompt_test.rb` test_render_names_the_finding_and_the_rules, test_render_is_short_and_leaves_the_procedure_to_the_playbook, test_render_formats_due_at_in_utc, test_render_leaves_no_erb_tags
- DISP-14: `test/remediation_prompt_test.rb` test_schema_is_valid_draft_07_and_accepts_a_remediation_result, test_schema_fits_the_session_request_limit
- DISP-23: `test/remediation_prompt_test.rb` test_render_of_a_same_major_finding_has_the_same_major_language, test_render_of_a_same_major_finding_is_byte_identical_to_the_pre_major_path_prompt, test_render_of_a_major_version_finding_has_the_major_path_language, test_render_of_a_major_version_finding_asks_for_breaking_changes_and_tests_run_in_the_close, test_render_of_a_same_major_finding_does_not_ask_for_breaking_changes_or_tests_run
- DISP-24: `test/remediation_prompt_test.rb` test_schema_accepts_breaking_changes_and_tests_run, test_schema_accepts_output_without_breaking_changes_or_tests_run
- DISP-25: `test/playbook_test.rb` test_body_keeps_every_rule_of_the_full_prompt, test_body_handles_both_major_version_cases, test_body_has_the_recommended_sections
- DISP-15: `test/webhook_test.rb` test_opened_with_auto_dispatch_starts_one_session
- DISP-16: `test/webhook_test.rb` test_opened_without_auto_dispatch_records_only_the_finding
- DISP-17: `test/webhook_test.rb` test_auto_dispatch_failure_keeps_the_finding_and_logs_the_error, test_auto_dispatch_without_a_playbook_id_keeps_the_finding_and_logs_the_error
- DISP-18: `test/webhook_test.rb` test_auto_dispatch_of_an_unfixable_finding_creates_nothing, test_auto_dispatch_skips_a_finding_whose_fix_branch_exists
- DISP-19: `test/devin_client_test.rb` test_not_found_raises_devin_api_error
- DISP-20: `test/devin_client_test.rb` test_list_repositories_uses_v3beta1_and_maps_structs
- DISP-21: unproven (the wiring in `bin/dispatch` has no tests)
- DISP-22: unproven (the wiring in `bin/dispatch` has no tests)
- DISP-26: `test/devin_client_test.rb` test_list_playbooks_gets_the_org_playbooks_and_maps_structs, test_create_playbook_posts_title_body_macro_and_schema, test_update_playbook_puts_title_body_macro_and_schema; `test/playbook_test.rb` test_current_compares_title_macro_body_and_schema (the wiring in `bin/playbook-sync` has no tests)

</details>
