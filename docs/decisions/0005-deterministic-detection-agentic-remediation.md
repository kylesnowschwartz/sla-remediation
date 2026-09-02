# 5. Detection is a script; remediation is the agent

Status: accepted, 2026-09-02

## Context

Detection decides what work exists and starts the SLA clock, so it has to be cheap and give the same answer every time. Remediation needs judgment: regenerate the lockfile or edit one line, what to do when an upgrade changes an API, how to verify it.

## Decision

`bin/scan` is plain Ruby around `pip-audit --format json`. pip-audit reports advisory IDs and fix versions but not severity, so the scanner looks each advisory up in the GitHub Advisory Database (`GET /advisories/{ghsa_id}`, which returns low, medium, high, or critical) and gives the package the highest severity among its advisories. It computes the due date from `SECURITY-SLA.md` and files one labeled issue per package, rendering the body from a markdown template (`templates/finding_issue.md.erb`) that includes the fenced `yaml` block. No model is involved. Devin only gets involved once an issue exists, with a prompt rendered from a markdown template (`prompts/remediate_dependency.md.erb`) that names the package, versions, and advisories and sets the rules: branch name, lockfile handling, verification, what goes in the pull request, and what not to touch. A package with no fixed release gets an issue saying so and isn't sent to Devin.
