# 8. CI failures go back to the session that opened the pull request

Status: accepted, 2026-09-03

## Context

The tracker recorded a pull request's check result and the status page showed `[CI FAILING]`, and that was where it stopped. On the flask upgrade (fork PR #21) the integration tests failed with `ImportError: cannot import name 'escape' from 'flask'` in two test files, and the pull request sat red until a human read the failing job and told Devin. The finding's clock kept running the whole time.

## Decision

When the tracker sees an open pull request's checks turn red at a head commit it has not sent back yet, it reads the failed check runs from GitHub (name, URL, first 40 lines of the summary), renders `prompts/repair_ci.md.erb`, and sends it as a message to the same Devin session that opened the pull request, asking it to fix the failures on the same branch. The session pushes, CI reruns, and the tracker's existing loop judges the new commit. Nothing new is dispatched.

Three things decide the shape.

The session that made the change is the one that can fix it fastest. It already has the repository, the reasoning behind the pin, and the pull request; a new session would rebuild all of that before reading the failure. That is why sessions are now created `resumable: true`: a resumable session keeps its VM state after it stops, and a message to it resumes it, so the tracker can reach it after it has gone idle.

The tracker is where the CI result is known. It already polls the pull request's check runs and holds the only mapping from pull request to session (ADR 6: the service is the ledger). A GitHub Actions workflow on the fork would need Devin credentials in the fork, would have to ask this service which session to message, and would fire on every red run with no place to keep the once-per-commit bookkeeping.

The cap keeps a session from looping on a failure it cannot fix. One message per red head sha (`ci_repair_sha`), at most `MAX_CI_REPAIRS` (2) per session (`ci_repairs`). Past the cap the tracker logs it and the row stays `[CI FAILING]` for a human; inside it, the status page reads `[REPAIRING]` so the leader can tell a failure being worked on from one that is waiting for someone.

A message that fails to send is counted as an error and retried next round; the repair columns are written only after the message is accepted, so a failed send never spends a repair. A session that is still working when its checks go red is not interrupted either: the message, and the repair it spends, wait until the session stops.
