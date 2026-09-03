# Scan

`bin/scan` audits the target repository's Python pins and files one labelled issue per vulnerable package, each carrying a finding block that parses back without loss.

## Audit

- **SCAN-01** On run, audits target-repo `requirements/base.txt` at the requested ref (default `master`).
  - or the local file named by `--requirements`
- **SCAN-02** Runs pip-audit over the requirements text with every `-e` line removed.
  - flags `--disable-pip --no-deps --format json`; exit status 0 and 1 both count as success
- **SCAN-03** Any other pip-audit exit status → failure naming it and pip-audit's standard error.
- **SCAN-04** A report that is not JSON or has no `dependencies` list → failure, nothing filed.
- **SCAN-05** One finding per package with a GHSA-resolvable vulnerability, ordered by package name.
- **SCAN-06** GHSA id: the vulnerability's own `GHSA-` id, else the first such alias, else unresolvable.
- **SCAN-07** Each distinct GHSA id is looked up in GitHub's advisory database at most once per scan.
- **SCAN-08** Severity is the highest among a finding's advisories, and `low` when none carries one.
- **SCAN-09** Fix version: lowest clearing every advisory, compared as versions; none if any lacks one.

## Filing

- **SCAN-10** A finding with no open issue is filed in the target repo, labelled `sla-remediation`.
  - titled `[SLA <severity>] <package> <pinned> → <fix>`
  - or `[SLA <severity>] <package> <pinned>: no fixed release`
  - one printed line names the issue number and title
- **SCAN-11** An open `sla-remediation` issue naming the package → nothing filed; print that issue.
- **SCAN-12** An open labelled issue with no parseable finding block does not count as already filed.
- **SCAN-13** `--dry-run` prints each issue's title and body instead of creating it; no write to GitHub.
- **SCAN-14** The issue body states the pinned version, advisory count, and fix version or its absence.
  - the remediation window in days for the finding's severity, from the policy
  - every advisory with its GHSA id, CVE id when known, and summary
- **SCAN-15** The body ends with a fenced `yaml` block that parses back to the finding that produced it.
  - `package`, `pinned`, `fix_version` (`null` when none), `advisories`, `severity`, `source`, `ecosystem`

## Finding block

- **SCAN-16** The parser reads the first fenced `yaml` block in an issue body and ignores any later one.
- **SCAN-17** Parsing requires `package` and `severity`, and lower-cases the severity.
  - `fix_version` may be absent; `ecosystem` defaults to `pypi`
- **SCAN-18** No `yaml` block, invalid YAML, or a missing required field → failure naming what is missing.

## Policy

- **SCAN-19** The policy is `SECURITY-SLA.md` at the target repo root, at the requested ref.
  - its first `yaml` block's `sla_days` map gives whole days for `critical`, `high`, `medium`, `low`
- **SCAN-20** No `yaml` block or no `sla_days` → the policy fails with an error naming the file.
- **SCAN-21** A severity's window is answered whatever its case; an unknown severity fails.
- **SCAN-22** Due date is the opening time plus the severity's window in whole days.

## Command

- **SCAN-23** `bin/scan` names the missing variable on standard error and exits 1 when:
  - `SLA_REPO` is unset
  - `SLA_GITHUB_TOKEN` is unset without both `--dry-run` and `--requirements`

## Not specified

- The exact wording of printed lines and error messages.
- The prose of the issue body beyond the facts SCAN-14 names.
- The order of keys inside the finding block.
- The ref name `master`; it is a default, not a promise.

<details><summary>Proofs</summary>

- SCAN-01: `test/scanner_test.rb` test_run_reads_requirements_from_github_when_not_given
- SCAN-02: unproven (exercised only by hand)
- SCAN-03: unproven (exercised only by hand)
- SCAN-04: `test/audit_report_test.rb` test_invalid_json_raises
- SCAN-05: `test/scanner_test.rb` test_findings_are_sorted_by_package_and_fetch_each_advisory_once; `test/audit_report_test.rb` test_vulnerable_packages_are_the_four_seeded_pins, test_clean_packages_are_not_vulnerable
- SCAN-06: `test/audit_report_test.rb` test_ghsa_id_prefers_the_vulns_own_id, test_ghsa_id_is_nil_without_a_ghsa_alias
- SCAN-07: `test/scanner_test.rb` test_findings_are_sorted_by_package_and_fetch_each_advisory_once
- SCAN-08: `test/finding_test.rb` test_severity_is_the_highest_regardless_of_order; `test/scanner_test.rb` test_rendered_body_notes_when_no_advisory_carries_a_severity_rating
- SCAN-09: `test/finding_test.rb` test_fix_version_compares_as_a_version_not_a_string; `test/audit_report_test.rb` test_paramiko_has_no_fix_versions
- SCAN-10: `test/scanner_test.rb` test_run_files_one_labeled_issue_per_vulnerable_package
- SCAN-11: `test/scanner_test.rb` test_run_skips_packages_with_an_open_labeled_issue
- SCAN-12: `test/scanner_test.rb` test_run_skips_packages_with_an_open_labeled_issue
- SCAN-13: `test/scanner_test.rb` test_dry_run_prints_instead_of_posting
- SCAN-14: `test/scanner_test.rb` test_rendered_body_for_urllib3_lists_every_advisory, test_rendered_body_for_paramiko_says_there_is_no_fixed_release
- SCAN-15: `test/scanner_test.rb` assert_round_trips (via test_run_files_one_labeled_issue_per_vulnerable_package)
- SCAN-16: `test/finding_block_test.rb` test_parse_reads_the_recorded_issue_body, test_only_the_first_yaml_block_is_read
- SCAN-17: `test/finding_block_test.rb` test_missing_package_or_severity_raises, test_severity_is_lowercased, test_fix_version_may_be_nil, test_ecosystem_is_read_when_present
- SCAN-18: `test/finding_block_test.rb` test_body_without_a_block_raises, test_invalid_yaml_raises, test_missing_package_or_severity_raises
- SCAN-19: `test/policy_test.rb` test_fetch_loads_security_sla_from_the_repo_root, test_load_reads_sla_days_from_the_yaml_block, test_missing_or_non_integer_window_raises
- SCAN-20: `test/policy_test.rb` test_document_without_a_yaml_block_raises, test_block_without_sla_days_raises
- SCAN-21: `test/policy_test.rb` test_days_for_is_case_insensitive, test_unknown_severity_raises
- SCAN-22: `test/policy_test.rb` test_due_at_adds_the_window_in_days
- SCAN-23: unproven (the command-line entry point is exercised only by hand)

</details>
