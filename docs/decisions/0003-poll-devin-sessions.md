# 3. We poll Devin for session status

Status: accepted, 2026-09-02

## Context

The service creates Devin sessions through the API and needs to know when each one finishes, whether it opened a pull request, and what it reported. Devin has no outbound webhook for session events.

## Decision

A tracker thread polls `GET /v3/organizations/{org_id}/sessions/{session_id}` for each open session every 15 seconds and records `status`, `status_detail`, `acus_consumed` (Devin's compute billing unit), the first pull request, and `structured_output` once it's there. Sessions don't end on their own: when Devin finishes it posts its result and sits at `status` `running` with `status_detail` `waiting_for_user`, and later `suspended` with `inactivity`. So a session is done when it has stopped working (`waiting_for_user`, `suspended`, `exit`, or `error`) and either its structured output is present or it has a pull request. Whether it succeeded comes from the structured output and the pull request. A session that stops with neither is marked stalled and left for a person to look at. `structured_output` arrives as an object when a schema was given and as the string `"null"` when not, so the client normalises both.
