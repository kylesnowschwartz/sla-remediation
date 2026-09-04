# 6. We call the sessions API instead of configuring a Devin Automation

Status: accepted, 2026-09-02

## Context

Devin ships Automations: event triggers (Slack, GitHub pull request and comment events, Linear, schedules, a custom webhook) that start a session from a prompt. Its "Dependency Vulnerability Scanner" template already runs pip-audit, checks the GitHub Advisory Database, and opens fix pull requests on a daily schedule. So an Automation could plausibly do the remediation half of this project.

## Decision

An Automation answers is a trigger and a session. But this project's primary question is, are we within SLA window, and if not, where is it stuck. Answering that needs a record of each finding with a start time, a due date, a current state, and a closing event, and Automations have no such record and no API to create or read one.

So the split is: triggers start sessions; this service keeps the record and countdown to SLA breach. Today the trigger is a labelled GitHub issue delivered by webhook (decision 4); a Devin Automation on Dependabot alerts could be a second one later, and the rest of the service would not change. The service files the finding, starts the clock at detection, starts one session per finding with a short prompt and the Playbook, ignores duplicate events, polls the session and the pull request's checks, records the outcome, and shows every open finding against its due date. Devin is the worker inside that loop, called through the same sessions API an Automation would call.

Two consequences follow. Detection stays a script (decision 5) so the clock starts when the vulnerability is found. And "fixed" is defined by the record (a pull request whose checks pass before the due date), not by "a session finished".

Automations could take over the trigger. Two things keep the sessions API in place for now: an Automation's session cannot carry a structured-output schema, so its report would be prose rather than the JSON the tracker grades; and there is no Automation trigger for a labelled issue, only for comments, pull requests, checks and pushes. If Automations gain both, the dispatcher becomes an Automation and nothing else changes; the record and the countdown stay here.
