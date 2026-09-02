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

## Devin API client

`SLA::DevinClient` (`lib/sla/devin_client.rb`) wraps the Devin API v3 over Faraday: list repositories, create/fetch sessions, and list/send session messages, raising `SLA::DevinAPIError` on any non-2xx.
Repositories are served from `/v3beta1/organizations/{org}/repositories`; the `/v3/` path returns 404.
`Session#structured_output` is normalised: the API returns a JSON object when the session was created with a schema and the string `"null"` when it was not, so a Hash is kept, a String is `JSON.parse`d, and `nil` means no output yet.
`bin/devin-smoke` (needs `DEVIN_SERVICE_API_KEY_V3` and `DEVIN_ORG_ID`) lists repositories and fetches one known session read-only; without the variables it names the missing ones and exits 1.

## Dispatching

A dispatch (`SLA::Dispatcher`, `lib/sla/dispatcher.rb`) renders `prompts/remediate_dependency.md.erb` for one recorded finding, creates a Devin session through `DevinClient`, and inserts one `sessions` row for the finding; a unique index on `sessions.finding_id` means a finding is dispatched exactly once, ever.
The session is created with the issue title, `repos: [SLA_REPO]`, `tags: ["sla-remediation", "issue-<n>"]`, `schemas/remediation_result.json` as `structured_output_schema`, `max_acu_limit: 3`, and `resumable: false`.
Before creating a session the dispatcher asks GitHub whether `fix/<package>-sla-<issue_number>` already exists as a branch or an open pull request in `SLA_REPO`; if so the finding counts as already dispatched.
With `SLA_AUTO_DISPATCH=true` the webhook dispatches every finding it records (result logged as `dispatch=` on the delivery line); by default it only records the finding.
A failed auto-dispatch (logged as `dispatch=error (<message>)`) keeps the finding row, creates no session, and is not retried automatically; retry it by hand with `bin/dispatch <issue_number>`.
`bin/dispatch <issue_number>` (needs `DEVIN_SERVICE_API_KEY_V3`, `DEVIN_ORG_ID`, `SLA_REPO`) dispatches one finding by hand and exits 0 for `dispatched` or `already_dispatched`; `--dry-run` prints the rendered prompt and the request payload as JSON without creating anything.
Findings with no fix version (`fix_version: null` in the finding block) are never dispatched: the dispatcher returns `not_fixable` and creates nothing.

## Tracking

The tracker (`SLA::Tracker`, `lib/sla/tracker.rb`) is a separate process from the web server: `bin/track --loop` polls every open session every 15 s, and `docker compose` runs it as its own service. It needs `DEVIN_SERVICE_API_KEY_V3` and `DEVIN_ORG_ID`; `bin/track` without `--loop` runs one round and prints the summary (`polled= settled= stalled= notified= errors=`).
Each round records `status`, `status_detail`, `acus_consumed`, the first pull request's URL and state, and the structured output on the `sessions` row, and logs one line when a session's status changes.
A session is judged `settled` once it has stopped working (`waiting_for_user`, `suspended`, `exit`, or `error`) with a structured output or a pull request, and `stalled` once it has stopped with neither; either outcome closes the row and it is never fetched again.
The first time a row has a pull request the notifier comments on the finding's issue (pull request link, session link, due date and whether it is inside or past the SLA window); `pr_notified_at` is written before the comment is posted and cleared if posting fails, so the comment is posted exactly once.
The comment needs `SLA_GITHUB_TOKEN`; without it the `Null` notifier is used and nothing is posted.
A structured output that does not match `schemas/remediation_result.json` is kept as JSON text in `structured_output_invalid` with a logged warning naming the first problem; nothing is discarded.
