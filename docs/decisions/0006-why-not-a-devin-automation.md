# 6. We call the sessions API instead of configuring a Devin Automation

Status: accepted, 2026-09-02

## Context

Devin ships Automations: event triggers (Slack, GitHub pull request and comment events, Linear, schedules, a custom webhook) that start a session from a prompt. Its "Dependency Vulnerability Scanner" template already runs pip-audit, checks the GitHub Advisory Database, and opens fix pull requests on a daily schedule. So an Automation could plausibly do the remediation half of this project out of the box, and the question a reviewer will ask is what this service adds.

## Decision

An Automation answers one question: did the trigger fire, and did a session run. The engineering leader's question is a different one: is every finding inside its SLA window, and if not, where is it stuck. Answering that needs a record of each finding with a start time, a due date, a current state, and a closing event, and Automations have no such record and no API to create or read one.

So the split is: the Automation is the trigger; this service is the ledger and the clock. It files the finding, starts the clock at detection, starts one session per finding with a rendered brief and a structured-output schema, ignores duplicate events, polls the session and the pull request's checks, records the outcome, and shows every open finding against its due date. Devin is the worker inside that loop, called through the same sessions API an Automation would call.

Two consequences follow. Detection stays a script (ADR 5) so the clock starts when the vulnerability is found, not at the next scheduled run. And "fixed" is defined by the ledger (a pull request whose checks pass, merged before the due date), not by "a session finished".

If Automations gain an API and an issue-labelled trigger, the dispatcher is the one component that could be replaced by one; the ledger would not be.
