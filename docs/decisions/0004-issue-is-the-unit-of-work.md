# 4. A labeled GitHub issue is the unit of work

Status: accepted, 2026-09-02

## Context

Findings can come from a scanner run, from a person, or later from Dependabot alerts. We need one representation they can all produce, that people can read and discuss, and that fires a webhook.

## Decision

A finding is a GitHub issue on the target repo with the `sla-remediation` label and a fenced `yaml` block in the body: `package`, `pinned`, `fix_version`, `advisories`, `severity`, `source`. The service acts on `issues` webhooks: `opened` with the label or `labeled` with `sla-remediation` starts a remediation, and `closed` marks it done (GitHub closes the issue when the `Fixes #n` pull request merges). Both `opened` and `labeled` fire when an issue is created with the label, so there's a unique constraint on issue number and the second event is a no-op. The service works out the due date itself from `SECURITY-SLA.md` and the issue's creation time.
