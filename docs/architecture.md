# Architecture

Every box is a named actor; every arrow is one directed data flow. The rendered copy is `architecture.png`; regenerate it with `mmdc -i architecture.mmd -o architecture.png -b white -s 2 -w 1600`.

```mermaid
flowchart LR
  subgraph fork["GitHub fork: kylesnowschwartz/superset"]
    direction TB
    SLA[SECURITY-SLA.md<br/>+ policy issue]; ISS[Issues<br/>label: sla-remediation<br/>yaml finding block]
    PR[Pull requests]
    PR --> CI[Actions CI]
  end
  subgraph svc["sla-remediation service (Ruby, Docker)"]
    direction TB
    RX[Webhook receiver<br/>HMAC verify, event filter]
    TRI[Triage<br/>parse finding block<br/>start SLA clock]
    DSP[Dispatcher<br/>render prompt template<br/>POST /sessions + schema + tags]
    TRK[Tracker<br/>poll every 15 s<br/>validate structured_output]
    DB[(SQLite<br/>findings, sessions)]
    UI[Status page<br/>GET / HTML]
    RX --> TRI --> DSP
    TRI --> DB
    TRK --> DB
    DB --> UI
  end
  subgraph devin["Devin"]
    direction TB
    API[Devin API v3]
    VM[Devin session<br/>bump pin, verify, open PR<br/>emit structured output]
    API --> VM
  end
  SCAN[bin/scan<br/>pip-audit → issues] -- files labeled issue --> ISS
  ENG([Engineer applies label]) --> ISS
  ISS -- webhook via smee.io --> RX
  DSP -- create session --> API
  TRK <-- poll GET /sessions/:id --> API
  VM -- opens PR --> PR
  TRK -- comment: PR link + status --> ISS
  REV([Reviewer<br/>localhost:4567]) --> UI
```

## Data flow

1. `bin/scan` or an engineer files a labelled issue with a finding block.
2. smee forwards the signed GitHub webhook to `POST /webhooks/github`.
3. Triage parses the finding, calculates its due date, and stores it once.
4. The dispatcher renders `prompts/` and creates a resumable Devin session with `schemas/`.
5. Devin upgrades the pin, checks it, opens a pull request, and reports its result.
6. The tracker polls Devin, validates the result, and records session and pull-request state.
7. The tracker comments on the issue when it first sees the pull request.
8. When the pull request's checks are red, the tracker sends the failed runs back to the same session, once per red commit and at most twice ([decision 8](decisions/0008-ci-failures-go-back-to-the-session.md)).
9. The status page reads SQLite and shows each finding's SLA state.

## Boundaries

- Only `DevinClient` and `GitHubClient` know HTTP; both are tested against recorded fixtures.
- `Policy` owns SLA date math; `FindingBlock` owns finding-block parsing, and nothing else parses issue bodies.
- The prompt templates and structured-output schema are files under `prompts/` and `schemas/`, reviewable instead of string literals. `RemediationPrompt` renders the dispatch prompt and `RepairPrompt` the CI-repair message; the tracker composes no message text.

[Behavioural specifications](spec/README.md) define each slice's promises.
