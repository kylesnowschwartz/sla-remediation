# Demo fixture

`bin/demo-export` writes the findings and sessions tables to `db/fixtures/demo.json`; `bin/demo-load` reads that file into an empty database with every timestamp moved forward so the run appears to have just ended. Together they fill the status page for a reader with no credentials.

## Export

- **FIXTURE-01** Writes every row and every column of `findings` and `sessions`, timestamps as ISO 8601 UTC strings.
  - Top-level `note` says nothing in the file is secret and names the export time.

## Load

- **FIXTURE-02** Moves every timestamp forward by one amount, so the newest `pr_checks_at` or `pr_merged_at` lands at load time.
  - Every interval between events is the one the run had; the status page reads the same SLA word per finding as at capture time.
- **FIXTURE-03** No check or merge time in the file → anchors on the newest timestamp of any kind.
- **FIXTURE-04** Either table already has rows → writes nothing and says so.
  - With `--replace`: deletes every sessions row, then every findings row, reports what it deleted, then loads.
- **FIXTURE-05** Reports how many findings and sessions it loaded and by how many seconds it shifted them.
- **FIXTURE-06** `bin/demo-load` exits 1 when the fixture file is missing, or the database is not empty and `--replace` was not given.

## Not specified

- The fixture's contents; `db/fixtures/demo.json` is whatever the last `bin/demo-export` captured.
- `id` collisions with rows inserted after loading; the tracker never runs against a loaded database.

<details><summary>Proofs</summary>

- FIXTURE-01: `test/demo_fixture_test.rb` test_export_writes_every_row_of_both_tables_with_iso_8601_utc_timestamps
- FIXTURE-02: `test/demo_fixture_test.rb` test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later, test_load_keeps_every_interval_between_events
- FIXTURE-03: `test/demo_fixture_test.rb` test_load_without_any_check_or_merge_time_anchors_on_the_newest_timestamp
- FIXTURE-04: `test/demo_fixture_test.rb` test_load_refuses_when_a_table_already_has_rows, test_load_with_replace_empties_both_tables_first
- FIXTURE-05: `test/demo_fixture_test.rb` test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later, test_load_of_an_empty_fixture_inserts_nothing
- FIXTURE-06: unproven

</details>
