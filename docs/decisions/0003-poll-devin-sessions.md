# 3. We poll Devin for session status

Status: accepted, 2026-09-02

## Context

The service creates Devin sessions through the API and needs to know when each one finishes, whether it opened a pull request, and what it reported. Devin has no outbound webhook for session events.

## Decision

A tracker thread polls `GET /v3/organizations/{org_id}/sessions/{session_id}` for each open session every 15 seconds and records `status`, `status_detail`, `acus_consumed` (Devin's compute billing unit), the first pull request, and `structured_output` once it's there. A session is done when `status` is `exit` or `error`; whether it succeeded comes from the structured output and the pull request. A session that's `suspended` for `inactivity` is marked stalled and left for a person to look at.
