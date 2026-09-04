# sla-remediation

A Ruby service that turns vulnerable Python pins into GitHub issues, starts a Devin session for each fixable finding, tracks its pull request, and shows whether the work meets the repository's security SLA.

## Why

Vulnerabilities pile up when nobody owns the fix. The target repo's [`SECURITY-SLA.md`](https://github.com/kylesnowschwartz/superset/blob/master/SECURITY-SLA.md) names a deadline per severity;
this service makes that deadline visible and hands routine fixes to Devin ([decision 1](docs/decisions/0001-sla-policy-lives-in-the-repo.md)).

## What it does

- `bin/scan` finds vulnerable pins and files labelled issues containing a fenced `yaml` finding block.
- The GitHub webhook verifies its signature, reads `SECURITY-SLA.md`, and records the finding and due date in SQLite.
- The dispatcher starts one Devin session; the tracker follows its result, pull request, checks, and SLA outcome, and sends CI failures back to the session.

The remediation procedure lives in a Devin Playbook that `bin/playbook-sync` creates from `prompts/remediate_dependency.playbook.md` and keeps up to date; it prints the `DEVIN_PLAYBOOK_ID` for `.env`. Each session is attached to that playbook and its prompt carries only the finding's facts (`prompts/remediate_dependency.md.erb`), so the security team edits the procedure in Devin without touching this service ([decision 9](docs/decisions/0009-procedure-lives-in-a-devin-playbook.md)).

[Behavioural specifications](docs/spec/README.md) state exactly what each slice promises. [Architecture](docs/architecture.md) shows the actors and data flow.

## Try it without credentials

The status page can be filled from a captured run, with no GitHub token, webhook secret, or Devin key. With Docker and the Compose plugin installed:

```sh
docker compose up app --build --detach --wait
docker compose run --rm app bin/demo-load
```

Open http://localhost:4567. This is the status page from a real run against `kylesnowschwartz/superset`, with every timestamp shifted so the capture happened at the moment you loaded it; the intervals between events are the run's own, so every SLA word is the one the run earned and the page ages from here as a live run would. `SLA_REPO` can stay unset. Expand a row to see the session's report and the pull request's checks. Nothing is read from GitHub and no Devin session is started; the tracker is left out because the loaded sessions are already closed.

`bin/demo-load` refuses to write into a database that already has findings or sessions; `bin/demo-load --replace` empties both tables first. The fixture is `db/fixtures/demo.json`, written by `bin/demo-export`; nothing in it is secret. See [Demo fixture](docs/spec/demo-fixture.md).

## Run with Docker

You need Docker with the Compose plugin (`docker compose version`) and a value for each variable in `.env.example`; [Run it against your own fork](#run-it-against-your-own-fork) says where each one comes from. Copy `.env.example` to the ignored `.env` and fill it in; Compose reads it for the containers' environment and for `${SMEE_URL}` in the compose file.

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

The web server and tracker share SQLite on the `sla-db` volume. `docker compose down -v` deletes it. The `app` service also mounts `db/fixtures/`, so a fixture written inside the container lands in the working tree.

## Run it against your own fork

1. Fork `kylesnowschwartz/superset`, not `apache/superset`, so that `SECURITY-SLA.md`, the `sla-remediation` and `policy` labels, and the seeded pins in `requirements/base.txt` come along. Nothing is ever opened against `apache/superset`.
2. Create a fine-grained GitHub personal access token scoped to the fork with read and write access to contents, issues, and pull requests. This is `SLA_GITHUB_TOKEN`. Without it the first `SECURITY-SLA.md` read counts against GitHub's anonymous rate limit and can fail on a shared network.
3. Get a Devin API v3 *service* key and the `org-...` organization ID: in Devin's organization settings, create a service user and an API key for it. Personal keys do not work with v3. These are `DEVIN_SERVICE_API_KEY_V3` and `DEVIN_ORG_ID`. With both in the environment, `bin/playbook-sync` creates the remediation playbook in the organization and prints `DEVIN_PLAYBOOK_ID`.
4. Create a smee channel with `curl -sI https://smee.io/new | grep -i location`; the `Location` URL is `SMEE_URL`. On the fork, open Settings → Webhooks → Add webhook. Set the payload URL to that URL, content type to `application/json`, secret to a random string you keep as `SLA_WEBHOOK_SECRET`, and events to "Issues" only.
5. Set `SLA_REPO` to the fork's `owner/name` in `.env`, along with the values above, and `SLA_AUTO_DISPATCH=true` if a labelled issue should start a Devin session on its own.
6. Start the services, put the fork in its starting state, and scan it:

   ```sh
   docker compose up --build --detach --wait
   docker compose run --rm app bin/demo-reset
   docker compose run --rm app bin/scan
   ```

The scan files one issue per vulnerable pin, the webhook reaches the service through smee, each finding starts a Devin session, and http://localhost:4567 follows the pull requests as they open and their checks run.

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

The shell or `.env` supplies these variables.

- `DEVIN_SERVICE_API_KEY_V3`: Devin v3 service-user key for creating and polling sessions.
- `DEVIN_ORG_ID`: organization in which sessions are created.
- `DEVIN_PLAYBOOK_ID`: id of the remediation playbook, printed by `bin/playbook-sync`.
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

After a good run, before the reset, `bin/demo-export` writes the findings and sessions to `db/fixtures/demo.json` for [Try it without credentials](#try-it-without-credentials); under Compose that is `docker compose run --rm app bin/demo-export`. It refuses to write from an empty database.

## Service slices

- [Scan](docs/spec/scan.md): audit pins and file one issue per vulnerable package.
- [Receive](docs/spec/receive.md): verify a webhook and record its finding and due date.
- [Dispatch](docs/spec/dispatch.md): create at most one resumable Devin session per fixable finding; `bin/dispatch <issue_number> --dry-run` prints its prompt and request.
- [Track](docs/spec/track.md): poll sessions every 15 seconds, validate `schemas/remediation_result.json`, follow checks, comment once, and send red checks back to the session at most twice.
- [Status page](docs/spec/status-page.md): calculate counts and the SLA state shown by `GET /`.
- [Demo reset](docs/spec/demo-reset.md): return the fork and database to their seeded state.
- [Demo fixture](docs/spec/demo-fixture.md): capture a run to a file and load it back, shifted to the present.

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
- [8. CI failures go back to the session that opened the pull request](docs/decisions/0008-ci-failures-go-back-to-the-session.md)
- [9. The remediation procedure lives in a Devin Playbook, not in the prompt](docs/decisions/0009-procedure-lives-in-a-devin-playbook.md)

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
