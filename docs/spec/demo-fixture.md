# Demo fixture

`bin/demo-export` writes the findings and sessions tables to
`db/fixtures/demo.json`, and `bin/demo-load` reads that file into an empty
database with every timestamp moved forward so the run appears to have just
ended. Together they fill the status page for a reader who has no
credentials.

## Export

**FIXTURE-01** THE export SHALL write every row and every column of the
`findings` and `sessions` tables, with every timestamp as an ISO 8601 UTC
string, under a top-level `note` that says nothing in the file is secret and
names the export time.
Proof: test/demo_fixture_test.rb test_export_writes_every_row_of_both_tables_with_iso_8601_utc_timestamps

## Load

**FIXTURE-02** THE load SHALL move every timestamp in the file forward by one
amount, chosen so that the newest `pr_checks_at` or `pr_merged_at` lands at
load time, so every interval between events is the one the run had and the
status page reads the same SLA word for each finding as it did when the
fixture was captured.
Proof: test/demo_fixture_test.rb test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later,
test_load_keeps_every_interval_between_events

**FIXTURE-03** IF the file records no check or merge time, THEN THE load
SHALL anchor on the newest timestamp of any kind.
Proof: test/demo_fixture_test.rb test_load_without_any_check_or_merge_time_anchors_on_the_newest_timestamp

**FIXTURE-04** IF either table already has rows, THEN THE load SHALL write
nothing and say so, unless `--replace` is given, in which case it SHALL
delete every sessions row and then every findings row before loading and
report what it deleted.
Proof: test/demo_fixture_test.rb test_load_refuses_when_a_table_already_has_rows,
test_load_with_replace_empties_both_tables_first

**FIXTURE-05** THE load SHALL report how many findings and sessions it
loaded and by how many seconds it shifted them.
Proof: test/demo_fixture_test.rb test_load_puts_the_rows_back_and_the_page_reads_the_same_words_days_later,
test_load_of_an_empty_fixture_inserts_nothing

**FIXTURE-06** `bin/demo-load` SHALL exit 1 when the fixture file is missing
or the database is not empty without `--replace`.
Proof: unproven

## Unproven

FIXTURE-06.

## Not specified

- The fixture's contents; `db/fixtures/demo.json` is whatever the last
  `bin/demo-export` captured.
- Behaviour when the fixture's `id` values collide with rows inserted after
  loading; the tracker never runs against a loaded database.
