# 7. A smee.io channel relays GitHub webhooks to the developer's machine

Status: accepted, 2026-09-02

## Context

GitHub delivers webhooks to a public URL. The service runs wherever `docker compose up` is run, usually a developer's machine with no public address, and the demo has to work from a fresh clone without anyone setting up a tunnel or a host.

## Decision

The fork's webhook points at a smee.io channel. smee is a free relay run by GitHub's Probot team: GitHub posts to the channel, and the `smee` client running next to the service (its own container in `docker compose`) holds an outbound connection, pulls each delivery down, and posts it to `localhost:4567/webhooks/github`. Nothing inbound is opened.

The channel is unauthenticated, so anyone with the URL can read the traffic or post to it. That's acceptable because the payloads are issue events from a public repository, and because the service doesn't trust the channel: every delivery has to carry a valid `X-Hub-Signature-256` from the webhook secret, and anything else gets a 401 before it's parsed. The signature check is the security boundary, not the relay.

smee is for development and the demo only. In production the same endpoint sits behind the team's normal ingress and the relay goes away; the code doesn't change.
