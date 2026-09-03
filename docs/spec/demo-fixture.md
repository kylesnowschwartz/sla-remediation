# Demo fixture

`bin/demo-export` writes the findings and sessions tables to `db/fixtures/demo.json`; `bin/demo-load` reads that file into an empty database with every timestamp moved forward so the capture appears to have just happened. Together they fill the status page for a reader with no credentials.

## Export

- **FIXTURE-01** Writes every row and every column of `findings` and `sessions`, timestamps as ISO 8601 UTC strings.
  - Top-level `note` says nothing in the file is secret and names the export time; top-level `exported_at` carries it for the load.
- **FIXTURE-07** Both tables empty → writes nothing and says so; `bin/demo-export` exits 1.

## Load

- **FIXTURE-02** Moves every timestamp forward by one amount, so the file's `exported_at` lands at load time.
  - Every interval between events is the one the run had; the status page reads the same SLA word per finding as at capture time, and a due date still ahead at capture is still ahead by the same margin.
- **FIXTURE-03** With `SLA_REPO` unset, the status page names the repository the loaded findings' issue URLs point at.
- **FIXTURE-04** Either table already has rows → writes nothing and says so.
  - With `--replace`: deletes every sessions row, then every findings row, reports what it deleted, then loads.
- **FIXTURE-05** Reports how many findings and sessions it loaded and by how many seconds it shifted them.
- **FIXTURE-06** `bin/demo-load` exits 1 when the fixture file is missing, or the database is not empty and `--replace` was not given.

## Not specified

- The fixture's contents; `db/fixtures/demo.json` is whatever the last `bin/demo-export` captured.
- `id` collisions with rows inserted after loading; the tracker never runs against a loaded database.

<details><summary>Proofs</summary>

- FIXTURE-01: `test/demo_fixture_test.rb` test_export_writes_every_row_of_both_tables_with_iso_8601_utc_timestamps
- FIXTURE-02: `test/demo_fixture_test.rb` test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later, test_load_keeps_every_interval_between_events, test_load_anchors_on_the_export_time_so_a_due_date_ahead_of_it_stays_ahead
- FIXTURE-03: `test/demo_fixture_test.rb` test_the_page_names_the_fork_from_the_loaded_rows_when_sla_repo_is_unset; `test/status_page_test.rb` test_repo_falls_back_to_the_findings_issue_urls_when_none_is_given
- FIXTURE-04: `test/demo_fixture_test.rb` test_load_refuses_when_a_table_already_has_rows, test_load_with_replace_empties_both_tables_first
- FIXTURE-05: `test/demo_fixture_test.rb` test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later, test_load_of_an_empty_fixture_inserts_nothing
- FIXTURE-06: unproven
- FIXTURE-07: `test/demo_fixture_test.rb` test_export_refuses_an_empty_database (the exit code is unproven)

</details>
