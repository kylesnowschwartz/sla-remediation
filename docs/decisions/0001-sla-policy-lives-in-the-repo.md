# 1. Service Level Agreements are defined in this repo

Status: accepted, 2026-09-02

## Context

This repo contains a service that files dependency vulnerabilities as issues on a target repo and gets them fixed. To do that it needs to know how many days the team has for each level of severity.

## Decision

Every repo the service works on has a `SECURITY-SLA.md` at its root: a couple of paragraphs of explanation and a `yaml` block with the window in days for each severity. When a finding (issue/cve/dependabot patch pr) is filed, the service reads that block and sets the due date to the issue's creation, time plus the window (e.g. 24-hours).
