# Demo reset

`bin/demo-reset` returns the target repository and the local database to
the state before a run, so the pipeline can be shown again from a clean
start. It works in four steps, in this order, and prints one line for each
thing it did or found nothing to do.

## Pull requests

**RESET-01** THE reset SHALL close, without merging, every open pull request
whose head branch starts with `fix/`, and then delete that branch; pull
requests from any other branch SHALL not be touched.
Proof: test/demo_reset_test.rb test_happy_path_closes_restores_and_clears_everything,
test_pull_requests_not_from_a_fix_branch_are_left_alone

**RESET-02** IF there is no open `fix/` pull request, THEN THE reset SHALL
say so and make no write for this step.
Proof: test/demo_reset_test.rb test_pull_requests_not_from_a_fix_branch_are_left_alone,
test_a_second_run_finds_nothing_and_reports_zeros

## Issues

**RESET-03** THE reset SHALL post the comment "Closed by demo reset; the
finding will be re-filed by the next scan." on every open issue labelled
`sla-remediation` and then close it; issues with other labels SHALL not be
touched, and the reset SHALL only ask GitHub for issues with that label.
Proof: test/demo_reset_test.rb test_happy_path_closes_restores_and_clears_everything,
test_issues_with_other_labels_are_left_alone

**RESET-04** IF there is no open `sla-remediation` issue, THEN THE reset
SHALL say so and make no write for this step.
Proof: test/demo_reset_test.rb test_issues_with_other_labels_are_left_alone,
test_a_second_run_finds_nothing_and_reports_zeros

## Seeded pins

**RESET-05** THE reset SHALL read the file and branch named in
`demo/seeds.yml` and, for each listed package whose pin differs from its
seeded version, rewrite the `package==version` line to the seeded version,
committing every change in one commit with the message "chore: reseed
known-vulnerable pins for the remediation demo".
Proof: test/demo_reset_test.rb test_happy_path_closes_restores_and_clears_everything

**RESET-06** THE reset SHALL count and report only the pins it changed, and
leave every other line of the file as it was.
Proof: test/demo_reset_test.rb test_happy_path_closes_restores_and_clears_everything

**RESET-07** IF every listed pin already has its seeded version, THEN THE
reset SHALL make no commit and say the file already has the seeded pins.
Proof: test/demo_reset_test.rb test_pins_already_seeded_means_no_commit,
test_a_second_run_finds_nothing_and_reports_zeros

## Database

**RESET-08** THE reset SHALL delete every sessions row and then every
findings row, and report the total deleted.
Proof: test/demo_reset_test.rb test_happy_path_closes_restores_and_clears_everything

**RESET-09** IF both tables are already empty, THEN THE reset SHALL delete
nothing and say the database is already empty.
Proof: test/demo_reset_test.rb test_a_second_run_finds_nothing_and_reports_zeros

## Whole command

**RESET-10** THE reset SHALL return a summary with the counts `prs_closed`,
`branches_deleted`, `issues_closed`, `pins_restored`, and `rows_deleted`.
Proof: test/demo_reset_test.rb (every test asserts the summary)

**RESET-11** WHEN run a second time with nothing changed in between, THE
reset SHALL make no write to GitHub or the database and report zero for
every count.
Proof: test/demo_reset_test.rb test_a_second_run_finds_nothing_and_reports_zeros

**RESET-12** WHEN run as a dry run, THE reset SHALL perform the same reads,
make no write to GitHub, delete no rows, print each action as "would ...",
and report the counts a real run would have produced.
Proof: test/demo_reset_test.rb test_dry_run_only_reads_and_deletes_no_rows

**RESET-13** THE reset SHALL not run the scan.
Proof: unproven (an absence; no test asserts it)

**RESET-14** `bin/demo-reset` SHALL accept `--dry-run`, print the summary as
`key=value` pairs, and IF `SLA_GITHUB_TOKEN` or `SLA_REPO` is unset SHALL
name the missing variables and exit 1 without running.
Proof: unproven

## GitHub client behaviour this slice relies on

**RESET-15** THE GitHub client SHALL list open pull requests with their head
branch names and open issues by label, one page of up to 100 each.
Proof: test/github_client_test.rb test_open_pull_requests_lists_every_open_pull_with_its_head_branch,
test_open_issues_lists_labeled_open_issues

**RESET-16** THE GitHub client SHALL read a file's text together with its
blob sha, and replace a file on a branch in one commit given that sha.
Proof: test/github_client_test.rb test_file_with_sha_returns_the_decoded_text_and_the_blob_sha,
test_update_file_puts_the_encoded_content_with_message_sha_and_branch

**RESET-17** THE GitHub client SHALL treat any non-2xx response as an error
carrying the HTTP status and body.
Proof: test/github_client_test.rb test_not_found_raises_github_api_error,
test_branch_exists_raises_on_other_errors

## Unproven

RESET-13, RESET-14. The order of the two deletes in RESET-08 is also not
observable by test; both tables end empty either way.

## Not specified

- The wording of printed lines beyond the comment and commit message, which
  are promised because they appear on GitHub.
- Behaviour when a `fix/` pull request comes from another fork; the branch
  delete would fail and stop the run.
- Behaviour when the issue close fails after the comment posted; the
  comment would be posted again on the next run.
- Pagination beyond the first 100 pull requests or issues.
