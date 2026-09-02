# sla-remediation

A Ruby service that turns dependency vulnerabilities into fixed pull requests
inside a security SLA. A labeled GitHub issue on the target repo carries a
`yaml` finding block (`package, pinned, fix_version, advisories[], severity,
source`); the service receives the `issues` webhook, verifies its signature,
computes the due date from the repo's `SECURITY-SLA.md`, stores the finding
in SQLite, and starts a Devin session with a rendered prompt and a structured
output schema. A tracker polls each session every 15 s, records its status,
ACUs consumed, and pull request, comments on the issue with the PR link, and a
status page lists every finding against its SLA due date.

See [docs/architecture.md](docs/architecture.md) for the actors and data
flows, and [docs/decisions/](docs/decisions/) for the decision records.

## Run locally

```sh
bundle install
bundle exec rake      # test + lint
bin/server            # Puma on http://localhost:4567
```

`curl localhost:4567/healthz` returns `{"ok":true}`.

## Configuration

Loaded from `.envrc` via direnv:

- `DEVIN_SERVICE_API_KEY_V3` — Devin API v3 service-user key used to create and poll sessions.
- `SLA_GITHUB_TOKEN` — GitHub token for reading issues and commenting on them in the target repo.
- `SLA_WEBHOOK_SECRET` — shared secret for verifying `X-Hub-Signature-256` on incoming GitHub webhooks.
- `DEVIN_ORG_ID` — Devin organization ID that sessions are created under.
- `SLA_REPO` — `owner/name` of the GitHub repo whose findings the service remediates.

`SLA_DATABASE_URL` (optional) overrides the Sequel connection string; it defaults to `sqlite://db/sla.sqlite3`.
