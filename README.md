# sla-remediation

A Ruby service that turns vulnerable Python pins into GitHub issues, starts a Devin session for each fixable finding, tracks its pull request, and shows whether the work meets the repository's security SLA.

## Why

Vulnerabilities pile up when nobody owns the fix. The target repo's [`SECURITY-SLA.md`](https://github.com/kylesnowschwartz/superset/blob/master/SECURITY-SLA.md) names a deadline per severity;
this service makes that deadline visible and hands routine fixes to Devin ([decision 1](docs/decisions/0001-sla-policy-lives-in-the-repo.md)).

## What it does

- `bin/scan` finds vulnerable pins and files labelled issues containing a fenced `yaml` finding block.
- The GitHub webhook verifies its signature, reads `SECURITY-SLA.md`, and records the finding and due date in SQLite.
- The dispatcher starts one Devin session; the tracker follows its result, pull request, checks, and SLA outcome.

[Behavioural specifications](docs/spec/README.md) state exactly what each slice promises. [Architecture](docs/architecture.md) shows the actors and data flow.

## Run with Docker

You need Docker with Compose (`docker compose version`), plus:

- A GitHub fork with `SECURITY-SLA.md` and `requirements/base.txt`; the demo uses `kylesnowschwartz/superset`.
- A Devin API v3 service-user key and the `org-...` organization ID. In Devin's organization settings, create a service user and an API key for it; personal keys do not work with v3.
- A GitHub token with write access to contents, issues, and pull requests on the fork. A fine-grained token scoped to that repository is enough.
- A smee channel. Create one with `curl -sI https://smee.io/new | grep -i location` and use the `Location` URL.

On the fork, open Settings → Webhooks → Add webhook. Set the payload URL to the smee URL, content type to `application/json`, secret to a random `SLA_WEBHOOK_SECRET`, and events to "Issues" only.

### Start

Export the configuration below, or create the ignored `.env` file:

```sh
cp .env.example .env
docker compose up --build --detach --wait
```

Open http://localhost:4567/. `curl localhost:4567/healthz` returns `{"ok":true}`.

```sh
docker compose run --rm app bin/scan
docker compose run --rm app bin/demo-reset
docker compose run --rm app bin/dispatch <issue_number>
```

The web server and tracker share SQLite on the `sla-db` volume. `docker compose down -v` deletes it.

## Run without Docker

Install Ruby 3.3; `.ruby-version` names the exact patch release, and any 3.3.x satisfies the `Gemfile`. Install [`uv`](https://docs.astral.sh/uv/) because `bin/scan` runs pip-audit through `uvx`.

```sh
bundle install
bundle exec rake      # test + lint
bin/server            # Puma on http://localhost:4567
```

`curl localhost:4567/healthz` returns `{"ok":true}`. In separate terminals, run:

```sh
bin/track --loop
npx --yes smee-client --url "$SMEE_URL" --target http://localhost:4567/webhooks/github
```

## Configuration

The shell or `.env` supplies these variables; `.envrc` loads them through direnv.

- `DEVIN_SERVICE_API_KEY_V3`: Devin v3 service-user key for creating and polling sessions.
- `DEVIN_ORG_ID`: organization in which sessions are created.
- `SLA_GITHUB_TOKEN`: token for repository reads, issue comments, and demo reset.
- `SLA_WEBHOOK_SECRET`: secret used to verify `X-Hub-Signature-256`.
- `SLA_REPO`: target repository as `owner/name`.
- `SLA_AUTO_DISPATCH`: `true` dispatches recorded findings; unset records them without dispatching.
- `SMEE_URL`: channel read by the smee client.
- `SLA_DATABASE_URL`: optional Sequel URL; defaults to `sqlite://db/sla.sqlite3`, while Docker uses `sqlite:///app/data/sla.sqlite3`.

## Demo fork and reset

The demo targets `kylesnowschwartz/superset`; it never changes `apache/superset`. `demo/seeds.yml` lists deliberately vulnerable pins in `requirements/base.txt`; their advisories and upgrades are real.

`bin/demo-reset` closes unmerged `fix/` pull requests and deletes their branches, closes open `sla-remediation` issues, restores seeded pins on `master`, and clears local `sessions` and `findings`. It needs `SLA_REPO` and `SLA_GITHUB_TOKEN` with contents, issues, and pull-request write access.

`bin/demo-reset --dry-run` changes nothing. Repeated resets are safe. Start a fresh run with:

```sh
bin/demo-reset && bin/scan
```

## Service slices

- [Scan](docs/spec/scan.md): audit pins and file one issue per vulnerable package.
- [Receive](docs/spec/receive.md): verify a webhook and record its finding and due date.
- [Dispatch](docs/spec/dispatch.md): create at most one Devin session per fixable finding; `bin/dispatch <issue_number> --dry-run` prints its prompt and request.
- [Track](docs/spec/track.md): poll sessions every 15 seconds, validate `schemas/remediation_result.json`, follow checks, and comment once.
- [Status page](docs/spec/status-page.md): calculate counts and the SLA state shown by `GET /`.
- [Demo reset](docs/spec/demo-reset.md): return the fork and database to their seeded state.

## In production

- A scheduled reconcile lists open labelled issues and dispatches those without sessions instead of trusting webhook delivery.
- Normal inbound routing replaces smee; the endpoint and signature check stay the same.
- SQLite becomes a rebuildable cache or a real database.
- Merging uses GitHub auto-merge behind required checks; the service never merges.

## Decisions

- [1. Service Level Agreements are defined in this repo](docs/decisions/0001-sla-policy-lives-in-the-repo.md)
- [2. Demo findings are seeded, but the advisories are real](docs/decisions/0002-seeded-findings-are-real-advisories.md)
- [3. We poll Devin for session status](docs/decisions/0003-poll-devin-sessions.md)
- [4. A labeled GitHub issue is the unit of work](docs/decisions/0004-issue-is-the-unit-of-work.md)
- [5. Detection is a script; remediation is the agent](docs/decisions/0005-deterministic-detection-agentic-remediation.md)
- [6. We call the sessions API instead of configuring a Devin Automation](docs/decisions/0006-why-not-a-devin-automation.md)
- [7. A smee.io channel relays GitHub webhooks to the developer's machine](docs/decisions/0007-smee-relays-webhooks-in-development.md)

## Development

```sh
bundle exec rake        # tests and lint (rubocop, then the Herb ERB linter)
bundle exec rake test
bundle exec rake lint
npx --yes @herb-tools/linter views/ "templates/**/*.erb"
```

No API key may be committed. Devin keys start with `cog` and an underscore, so this must print nothing before pushing:

```sh
git grep -n 'cog[_]'
```
