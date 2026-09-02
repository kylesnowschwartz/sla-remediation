# Scan

`bin/scan` audits the target repository's Python pins with pip-audit and
files one labelled issue per vulnerable package. The issue is the unit of
work for everything downstream, so this slice's promise is that each issue
carries a finding block the receiver can parse back without loss.

## Audit

**SCAN-01** WHEN `bin/scan` runs, THE scanner SHALL audit
`requirements/base.txt` from the target repository at the requested ref
(default `master`), or the local file named by `--requirements`.
Proof: test/scanner_test.rb test_run_reads_requirements_from_github_when_not_given

**SCAN-02** THE scanner SHALL run pip-audit with `--disable-pip --no-deps
--format json` over the requirements text with every editable (`-e`) line
removed, and treat exit status 0 and 1 as success.
Proof: unproven

**SCAN-03** IF pip-audit exits with a status other than 0 or 1, THEN THE
scanner SHALL fail with an error naming the exit status and pip-audit's
standard error.
Proof: unproven

**SCAN-04** IF the audit report is not JSON or has no `dependencies` list,
THEN THE scanner SHALL fail rather than file anything.
Proof: test/audit_report_test.rb test_invalid_json_raises

**SCAN-05** THE scanner SHALL produce one finding per package that has at
least one vulnerability resolvable to a GHSA identifier, ordered by package
name.
Proof: test/scanner_test.rb test_findings_are_sorted_by_package_and_fetch_each_advisory_once;
test/audit_report_test.rb test_vulnerable_packages_are_the_four_seeded_pins,
test_clean_packages_are_not_vulnerable

**SCAN-06** THE scanner SHALL resolve a vulnerability's GHSA identifier from
its own id when that starts with `GHSA-`, otherwise from the first alias
that does, otherwise treat it as unresolvable.
Proof: test/audit_report_test.rb test_ghsa_id_prefers_the_vulns_own_id,
test_ghsa_id_is_nil_without_a_ghsa_alias

**SCAN-07** THE scanner SHALL look up each distinct GHSA identifier from
GitHub's advisory database at most once per scan.
Proof: test/scanner_test.rb test_findings_are_sorted_by_package_and_fetch_each_advisory_once

**SCAN-08** THE scanner SHALL give a finding the highest severity among its
advisories, and `low` when no advisory carries a severity.
Proof: test/finding_test.rb test_severity_is_the_highest_regardless_of_order;
test/scanner_test.rb test_rendered_body_notes_when_no_advisory_carries_a_severity_rating

**SCAN-09** THE scanner SHALL set a finding's fix version to the lowest
version that clears every advisory, comparing as versions rather than
strings, and to none when any advisory has no fixed release.
Proof: test/finding_test.rb test_fix_version_compares_as_a_version_not_a_string;
test/audit_report_test.rb test_paramiko_has_no_fix_versions

## Filing

**SCAN-10** WHEN a finding has no open issue, THE scanner SHALL create an
issue in the target repository labelled `sla-remediation`, titled
`[SLA <severity>] <package> <pinned> → <fix>` or
`[SLA <severity>] <package> <pinned>: no fixed release`, and print one line
naming the issue number and title.
Proof: test/scanner_test.rb test_run_files_one_labeled_issue_per_vulnerable_package

**SCAN-11** IF an open `sla-remediation` issue already names the package in
its finding block, THEN THE scanner SHALL file nothing for that package and
print one line naming the existing issue.
Proof: test/scanner_test.rb test_run_skips_packages_with_an_open_labeled_issue

**SCAN-12** IF an open labelled issue has no parseable finding block, THEN THE
scanner SHALL ignore it when deciding what is already filed.
Proof: test/scanner_test.rb test_run_skips_packages_with_an_open_labeled_issue

**SCAN-13** WHEN run with `--dry-run`, THE scanner SHALL print each issue's
title and body instead of creating it, and make no write to GitHub.
Proof: test/scanner_test.rb test_dry_run_prints_instead_of_posting

**SCAN-14** THE issue body SHALL state the pinned version, the number of
advisories, the fix version or that no fixed release exists, the remediation
window in days for the finding's severity from the policy, and list every
advisory with its GHSA id, CVE id when known, and summary.
Proof: test/scanner_test.rb test_rendered_body_for_urllib3_lists_every_advisory,
test_rendered_body_for_paramiko_says_there_is_no_fixed_release

**SCAN-15** THE issue body SHALL end with a fenced `yaml` finding block
holding `package`, `pinned`, `fix_version` (`null` when none),
`advisories`, `severity`, `source`, and `ecosystem`, such that parsing the
block back yields the finding that produced it.
Proof: test/scanner_test.rb assert_round_trips (via
test_run_files_one_labeled_issue_per_vulnerable_package)

## Finding block

**SCAN-16** THE finding-block parser SHALL read the first fenced `yaml` block
in an issue body and ignore any later one.
Proof: test/finding_block_test.rb test_parse_reads_the_recorded_issue_body,
test_only_the_first_yaml_block_is_read

**SCAN-17** THE finding-block parser SHALL require `package` and `severity`,
lower-case the severity, allow `fix_version` to be absent, and default
`ecosystem` to `pypi`.
Proof: test/finding_block_test.rb test_missing_package_or_severity_raises,
test_severity_is_lowercased, test_fix_version_may_be_nil, test_ecosystem_is_read_when_present

**SCAN-18** IF an issue body has no `yaml` block, or the block is not valid
YAML, or a required field is missing, THEN THE parser SHALL fail with an
error naming what is missing.
Proof: test/finding_block_test.rb test_body_without_a_block_raises,
test_invalid_yaml_raises, test_missing_package_or_severity_raises

## Policy

**SCAN-19** THE policy SHALL be read from `SECURITY-SLA.md` at the root of
the target repository at the requested ref, from the first `yaml` block's
`sla_days` map, which must give a whole number of days for each of
`critical`, `high`, `medium`, and `low`.
Proof: test/policy_test.rb test_fetch_loads_security_sla_from_the_repo_root,
test_load_reads_sla_days_from_the_yaml_block, test_missing_or_non_integer_window_raises

**SCAN-20** IF `SECURITY-SLA.md` has no `yaml` block or no `sla_days`, THEN
THE policy SHALL fail with an error naming the file.
Proof: test/policy_test.rb test_document_without_a_yaml_block_raises,
test_block_without_sla_days_raises

**SCAN-21** THE policy SHALL answer the window for a severity regardless of
its case, and fail for a severity it does not know.
Proof: test/policy_test.rb test_days_for_is_case_insensitive, test_unknown_severity_raises

**SCAN-22** THE policy SHALL compute a due date as the opening time plus the
severity's window in whole days.
Proof: test/policy_test.rb test_due_at_adds_the_window_in_days

## Command

**SCAN-23** IF `SLA_REPO` is unset, or `SLA_GITHUB_TOKEN` is unset without
both `--dry-run` and `--requirements`, THEN `bin/scan` SHALL name the
missing variable on standard error and exit 1.
Proof: unproven

## Unproven

SCAN-02, SCAN-03, SCAN-23. The pip-audit wrapper and the command-line entry
point have no tests; their behaviour is exercised only by hand.

## Not specified

- The exact wording of printed lines and error messages.
- The prose of the issue body beyond the facts SCAN-14 names.
- The order of keys inside the finding block.
- The ref name `master`; it is a default, not a promise.
