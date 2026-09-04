# 9. The remediation procedure lives in a Devin Playbook, not in the prompt

Status: accepted, 2026-09-04

## Context

Each session's prompt was seventy lines, and all but the first paragraph was the same for every finding: the branch rule, the lockfile route, the pip-audit check, the pull request rules, the forbidden actions. Changing a rule meant a pull request to this service. Devin has a Playbook: a stored, organization-owned procedure a session is attached to by id, with an optional structured-output schema, managed through the same v3 API the dispatcher uses.

## Decision

The procedure is a Playbook. Its body is `prompts/remediate_dependency.playbook.md`, plain markdown with no template slots; where a rule depended on the finding (a major-version upgrade), the playbook states both cases and the prompt says which applies. `bin/playbook-sync` finds the org's playbook by macro (`!remediate-pip`), creates or updates it from the repo, and prints `DEVIN_PLAYBOOK_ID`; the repo file is the source of truth, so an edit made in Devin is ported back or overwritten at the next sync. The prompt (`prompts/remediate_dependency.md.erb`) is now the facts of one finding plus "follow the attached playbook". There is no inline fallback: `DEVIN_PLAYBOOK_ID` is required and dispatch refuses without it, because keeping the full prompt too would mean the procedure living in two files that drift. The schema still goes on every session request, so grading doesn't depend on the playbook.
