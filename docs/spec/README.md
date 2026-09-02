# Behavioural specification

What the service promises to do, one statement per promise, each tied to the
test that proves it. The architecture document says how the parts fit
together and the decision records say why; this directory says what.

The specification describes the system as built. A change to behaviour
starts here: write or amend the statement, then change the code and its
test, then update the proof line.

## Files

One file per slice, in the order data flows through the system:

| File | Slice | Covers |
|---|---|---|
| [scan.md](scan.md) | Scan | pip-audit over the target repository's pins to a labelled issue per vulnerable package |
| [receive.md](receive.md) | Receive | a GitHub webhook delivery to a findings row with a due date |
| [dispatch.md](dispatch.md) | Dispatch | a finding to one Devin session |
| [track.md](track.md) | Track | polling sessions, recording results, commenting the pull request on the issue |
| [status-page.md](status-page.md) | Status page | the counts, the SLA word for each finding, and what each cell shows |
| [demo-reset.md](demo-reset.md) | Demo reset | returning the target repository and the database to the state before a run |

## Notation

Statements use the EARS sentence patterns (Easy Approach to Requirements
Syntax). The pattern tells the reader when the promise applies:

| Pattern | Meaning |
|---|---|
| `THE <part> SHALL <response>` | always true |
| `WHEN <event>, THE <part> SHALL <response>` | in response to an event |
| `IF <condition>, THEN THE <part> SHALL <response>` | in a state or on an unwanted input |
| `WHILE <state>, THE <part> SHALL <response>` | for as long as a state holds |

Each statement has an identifier such as `TRACK-03`: the slice prefix and a
number that is never reused. Below each statement one line names its proof:

- `Proof: test/tracker_test.rb test_settled_session_with_pull_request_and_output_is_recorded_and_notified_once` points at the test
  method that fails if the promise is broken.
- `Proof: unproven` means no automated test covers it yet. Unproven
  statements are listed together at the end of each file.

Each file ends with a "Not specified" list: things the code does today that
are incidental and not promised, so a reader knows where the contract stops.

## Vocabulary

- **Finding**: one vulnerable package pin in the target repository, recorded
  as one GitHub issue and one row in the `findings` table.
- **Finding block**: the fenced `yaml` block in the issue body that carries
  the package, pinned version, fix version, advisories, severity, and source.
- **Target repository**: the GitHub repository named by `SLA_REPO`, whose
  pins are scanned and whose issues and pull requests the service touches.
- **Policy**: `SECURITY-SLA.md` in the target repository, which sets the
  number of days a fix may take for each severity.
- **Due date**: when the finding was filed plus the policy's days for its
  severity.
- **Session**: one Devin session, recorded as one row in the `sessions`
  table, created for one finding.
- **Outcome**: the tracker's final judgement of a session, `settled` or
  `stalled`.
- **SLA word**: the one-word state the status page shows for a finding:
  `met`, `late`, `breached`, `stalled`, `in progress`, or `waiting`.
