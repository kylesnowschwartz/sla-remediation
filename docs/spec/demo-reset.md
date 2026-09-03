# Demo reset

`bin/demo-reset` returns the target repository and the local database to their pre-run state in four ordered steps, printing one line per step.

## Pull requests and issues

- **RESET-01** Closes each open `fix/` pull request without merging, deletes its branch.
  - Pull requests from any other branch are untouched.
- **RESET-02** No open `fix/` pull request → says so, no write for this step.
- **RESET-03** Comments on every open `sla-remediation` issue, then closes it; other labels untouched.
  - Comment: "Closed by demo reset; the finding will be re-filed by the next scan."
  - Asks GitHub only for issues carrying that label.
- **RESET-04** No open `sla-remediation` issue → says so, no write for this step.

## Seeded pins and database

- **RESET-05** Rewrites each drifted `package==version` line to its seeded version in one commit.
  - File and branch are the ones named in `demo/seeds.yml`.
  - Commit message: "chore: reseed known-vulnerable pins for the remediation demo".
- **RESET-06** Counts and reports only the pins it changed; every other line stays as it was.
- **RESET-07** Every listed pin already seeded → no commit, says the file already has the seeded pins.
- **RESET-08** Deletes every sessions row, then every findings row, and reports the total deleted.
- **RESET-09** Both tables already empty → deletes nothing, says the database is already empty.

## Whole command

- **RESET-10** Summary: `prs_closed`, `branches_deleted`, `issues_closed`, `pins_restored`, `rows_deleted`.
- **RESET-11** Second run, nothing changed → no GitHub or database write, every count zero.
- **RESET-12** Dry run does the same reads, writes nothing to GitHub, deletes no rows.
  - Prints each action as "would ...", and reports the counts a real run would have produced.
- **RESET-13** Does not run the scan.
- **RESET-14** `bin/demo-reset` accepts `--dry-run` and prints the summary as `key=value` pairs.
  - Unset `SLA_GITHUB_TOKEN` or `SLA_REPO` → names the missing variables, exits 1, runs nothing.

## GitHub client behaviour this slice relies on

- **RESET-15** Lists open pull requests with head branches and open issues by label, one page of up to 100.
- **RESET-16** Reads a file's text and blob sha; replaces a file on a branch in one commit with that sha.
- **RESET-17** Any non-2xx response → an error carrying the HTTP status and body.

## Not specified

- Wording of printed lines beyond the comment and commit message, which appear on GitHub.
- A `fix/` pull request from a fork: the branch delete would fail and stop the run.
- Issue close failing after the comment posted: the comment is posted again next run.
- Pagination beyond the first 100 pull requests or issues.

<details><summary>Proofs</summary>

- RESET-01: `test/demo_reset_test.rb` test_happy_path_closes_restores_and_clears_everything, test_pull_requests_not_from_a_fix_branch_are_left_alone
- RESET-02: `test/demo_reset_test.rb` test_pull_requests_not_from_a_fix_branch_are_left_alone, test_a_second_run_finds_nothing_and_reports_zeros
- RESET-03: `test/demo_reset_test.rb` test_happy_path_closes_restores_and_clears_everything, test_issues_with_other_labels_are_left_alone
- RESET-04: `test/demo_reset_test.rb` test_issues_with_other_labels_are_left_alone, test_a_second_run_finds_nothing_and_reports_zeros
- RESET-05: `test/demo_reset_test.rb` test_happy_path_closes_restores_and_clears_everything
- RESET-06: `test/demo_reset_test.rb` test_happy_path_closes_restores_and_clears_everything
- RESET-07: `test/demo_reset_test.rb` test_pins_already_seeded_means_no_commit, test_a_second_run_finds_nothing_and_reports_zeros
- RESET-08: `test/demo_reset_test.rb` test_happy_path_closes_restores_and_clears_everything (the order of the two deletes is not observable by test; both tables end empty either way)
- RESET-09: `test/demo_reset_test.rb` test_a_second_run_finds_nothing_and_reports_zeros
- RESET-10: `test/demo_reset_test.rb` (every test asserts the summary)
- RESET-11: `test/demo_reset_test.rb` test_a_second_run_finds_nothing_and_reports_zeros
- RESET-12: `test/demo_reset_test.rb` test_dry_run_only_reads_and_deletes_no_rows
- RESET-13: unproven (an absence; no test asserts it)
- RESET-14: unproven
- RESET-15: `test/github_client_test.rb` test_open_pull_requests_lists_every_open_pull_with_its_head_branch, test_open_issues_lists_labeled_open_issues
- RESET-16: `test/github_client_test.rb` test_file_with_sha_returns_the_decoded_text_and_the_blob_sha, test_update_file_puts_the_encoded_content_with_message_sha_and_branch
- RESET-17: `test/github_client_test.rb` test_not_found_raises_github_api_error, test_branch_exists_raises_on_other_errors

</details>
