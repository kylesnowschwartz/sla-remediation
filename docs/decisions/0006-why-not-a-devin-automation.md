# 6. We call the sessions API instead of configuring a Devin Automation

Status: accepted, 2026-09-02

## Context

Devin ships Automations: event triggers (Slack, GitHub PR and comment events, Linear, schedules, a custom webhook) that start a session from a prompt. Its "Dependency Vulnerability Scanner" template already runs pip-audit, checks the GitHub Advisory Database, and opens fix PRs on a daily schedule. So the question is what we're building that isn't already a form in the Devin UI.

## Decision

Devin Automations own "event fires, session starts". They don't know a finding exists, when its clock started, whether the PR merged, or whether the SLA was met, and there's no API to create or read them. The activity tab says whether a trigger fired, not whether we're inside the SLA.

This service owns the finding's lifecycle: it files the issue, starts the clock, starts the session with a rendered prompt and a structured output schema, ignores duplicate events, records the result, and shows every open finding against its due date. Devin is the remediation step inside that, called through the same sessions API an Automation would call. Detection stays a script rather than a scheduled agent so the clock starts at detection (ADR 5), not at the next daily run.

If Automations grow an API and an issue-labeled trigger, the dispatcher is the one component that could be replaced by one.
