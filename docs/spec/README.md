# Behavioural specification

What the service promises, one bullet per promise, each tied to the test that
proves it. [architecture.md](../architecture.md) says how the parts fit;
[decisions/](../decisions/) says why; this directory says what.

A behaviour change starts here: amend the bullet, change the code and test,
update the proof.

## Files

One per slice, in data-flow order:

| File | Slice |
|---|---|
| [scan.md](scan.md) | pip-audit over the target repo's pins → one labelled issue per vulnerable package |
| [receive.md](receive.md) | GitHub webhook delivery → a findings row with a due date |
| [dispatch.md](dispatch.md) | a finding → one Devin session |
| [track.md](track.md) | poll sessions, record results, follow the pull request, comment on the issue |
| [status-page.md](status-page.md) | counts, the SLA word per finding, what each cell shows |
| [demo-reset.md](demo-reset.md) | return the target repo and database to their pre-run state |

## Reading a file

- Each bullet is one promise with a stable ID such as `TRACK-03`; IDs are never reused.
- "When/If/While" opens a bullet that applies only on that event, condition, or state.
- The collapsed **Proofs** block at the end names the test method for each ID; `unproven` means no test yet.
- **Not specified** lists what the code does today but does not promise.

## Vocabulary

- **Finding**: one vulnerable pin, recorded as one GitHub issue and one `findings` row.
- **Finding block**: the fenced `yaml` block in the issue body (package, versions, advisories, severity, source).
- **Target repository**: the repo named by `SLA_REPO`, whose pins, issues, and pull requests the service touches.
- **Policy**: `SECURITY-SLA.md` in the target repo; days allowed per severity.
- **Due date**: filed time plus the policy's days for the finding's severity.
- **Session**: one Devin session, one `sessions` row, one finding.
- **Outcome**: the tracker's final judgement of a session: `reported` (stopped with a report or a pull request; not a judgement of the fix) or `stalled`.
- **SLA word**: the status page's one-word state: `met`, `late`, `breached`, `closed`, `repairing`, `ci failing`, `stalled`, `in progress`, `waiting`.
