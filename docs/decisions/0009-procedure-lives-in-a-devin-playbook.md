# 9. The remediation procedure lives in a Devin Playbook, not in the prompt

Status: accepted, 2026-09-04

## Context

Every session used to receive one prompt rendered from `prompts/remediate_dependency.md.erb`. Of its seventy-odd lines, the first paragraph named the finding; the rest was the same for every finding: branch off `master`, recompile the uv lockfile and fall back to a direct edit, strip `-e ./superset-core` before `pip-audit`, never open the pull request against `apache/superset`, say `Fixes #<issue>`, do not run the full suite, report the structured output. Changing a rule meant a pull request to this service, and reading a session's prompt in the Devin UI meant scrolling past the procedure to find the fact that differed.

Devin has a stored, organization-owned procedure that a session is attached to by id: a Playbook, with a title, a body, an optional `!macro`, and an optional structured-output schema, created and updated through the same v3 API the dispatcher already uses.

## Decision

The fixed procedure is a Playbook. `prompts/remediate_dependency.playbook.md` is its body, plain markdown with no template slots, in Devin's recommended shape (Procedure, Specifications, Advice, Forbidden Actions, Required from User). `bin/playbook-sync` finds the organization's playbook by macro (`!remediate-pip`), creates it when absent, updates it when the title, body, or schema differ, and prints `DEVIN_PLAYBOOK_ID` for `.env`. The session prompt (`prompts/remediate_dependency.md.erb`) is now the facts about one finding: repository, issue, package, versions, advisories, severity, due date, branch name, whether the fix crosses a major version, and one line saying to follow the attached playbook. `DEVIN_PLAYBOOK_ID` is required; without it dispatch refuses rather than sending the procedure inline.

Three things decide the shape.

The split follows who changes what. The facts change per finding and come from the ledger, so the service renders them. The procedure changes when the security team learns something (a new place a package can be pinned, a stricter verification), and the people who learn it should be able to edit it in Devin, where the sessions that follow it are visible, without a deploy of this service. The repository copy stays the source of truth: `bin/playbook-sync` is idempotent and overwrites a drifted playbook, so a rule edited in Devin is ported back to the markdown or lost at the next sync.

Where a rule branched on the finding, the branch moved into the procedure as prose ("if the task prompt says the fix crosses a major version, ... otherwise ...") and the prompt states which case applies. The playbook stays template-free, so the file the security team reads is the file Devin reads, byte for byte.

There is no inline fallback. Keeping the full prompt as a second template would have meant the procedure living in two files that drift, in exchange for dispatch working when the playbook has been deleted, which `bin/playbook-sync` repairs in one command. A missing id fails at the entrypoints (`bin/dispatch` names the variable and the script that prints it; the webhook's automatic dispatch logs the same and keeps the finding), never as a stack trace.

The structured-output schema still travels with every session request as well as on the playbook, so grading (ADR 6: the service is the ledger) does not depend on what the playbook currently carries. Tags, `resumable: true`, the ACU limit, and the reservation before the Devin call are unchanged. The CI-repair message (ADR 8) stays a rendered template: it is a message to a running session, not a procedure a session starts from.
