# SLA dependency remediation (pip-audit)

## Overview

Remediate one vulnerable Python pin that pip-audit reported in a fork of Apache Superset: raise the pin in `requirements/base.txt`, verify with pip-audit, and open a pull request that closes the finding's issue before its SLA due date. The task prompt supplies the facts about the finding; this playbook supplies the procedure.

## Procedure

1. Create a branch off `master` with the branch name the task prompt gives.
2. If the task prompt says the fix crosses a major version, update the package's pin in `requirements/base.txt` to the fix version, the lowest release of the new major series that clears the advisories. Otherwise, update the pin to a non-vulnerable version: at least the fix version, preferring the latest release in the same major series.
3. `requirements/base.txt` is a uv-compiled lockfile (see its header). Attempt the proper regeneration with `uv pip compile pyproject.toml requirements/base.in -o requirements/base.txt` (Python 3.11+ is required; install it with `uv python install 3.11` if needed). If the full recompile moves unrelated pins, fall back to editing the package's line directly and say so explicitly in the PR description.
4. If the task prompt says the fix crosses a major version, make the minimal changes to source and test files where the upgrade breaks them; keep such changes to the minimum the upgrade needs and explain each one in the PR description. Run the test files that import or exercise the changed code with `pytest <paths>` and report the result. If the suite cannot run in your environment, say so in the pull request and rely on CI; do not skip the change. Otherwise, keep the change limited to this package.
5. Verify the fix: strip the `-e ./superset-core` line into a temp file and run `pip-audit --disable-pip --no-deps -r` on that temp file; confirm the package is no longer flagged. Other pre-existing findings are out of scope — list them in the PR as out of scope, do not fix them.
6. Check nothing else pins or vendors the package (search `requirements/`, `pyproject.toml`, `superset-core/pyproject.toml`).
7. Open a pull request against `master` of the task prompt's repository only — never against `apache/superset`. Use the repository's PR template. The description must state: the advisory IDs, before/after versions, the verification result, and whether you regenerated the lockfile or edited the pin directly. Reference the issue with "Fixes #<issue number>".
8. When the pull request is open, provide your final structured output as described by the attached schema: the PR URL, the before/after versions, the advisories cleared, which lockfile route you took, and the pip-audit verification result. If the task prompt says the fix crosses a major version, also include every source or test file you changed with the reason (`breaking_changes`) and the test commands you ran (`tests_run`).

## Specifications

- One pull request from the named branch against `master` of the task prompt's repository, using the repository's PR template.
- The description states the advisory IDs, the before/after versions, the pip-audit verification result, and whether the lockfile was regenerated or the pin edited directly, and references the issue with "Fixes #<issue number>".
- For a fix that crosses a major version, the description names each dependency the new major version strictly requires and explains each source or test change.
- `requirements/base.txt` pins the package at a version that clears every advisory in the task prompt, and pip-audit no longer flags the package.
- Structured output matching the attached schema, provided once the pull request is open.

## Advice

- `requirements/base.txt` is a uv-compiled lockfile; its header says so. Recompile first with `uv pip compile pyproject.toml requirements/base.in -o requirements/base.txt`; edit the one line directly only when the recompile moves unrelated pins, and then say so in the PR description and report `direct_edit` as the lockfile route.
- pip-audit cannot resolve the editable `-e ./superset-core` line, so strip it into a temp file and run `pip-audit --disable-pip --no-deps -r` on that file.
- A package may be pinned or vendored outside `requirements/base.txt`: check `requirements/`, `pyproject.toml`, and `superset-core/pyproject.toml`.
- Pre-existing findings in other packages are out of scope; list them in the PR as out of scope.

## Forbidden Actions

- Never open a pull request against `apache/superset`; the pull request goes to the task prompt's repository only.
- Do not modify any other dependencies or source files. When the task prompt says the fix crosses a major version, the only exceptions are dependencies the new major version strictly requires (name each in the PR description) and the source changes the upgrade breaks; make no source changes beyond what the upgrade breaks.
- Do not run the full test suite; CI on the pull request runs the relevant unit tests.
- Do not fix pre-existing findings in other packages.

## Required from User

The task prompt supplies:

- the repository as `owner/name`, and the open issue's number and URL
- the package, its pinned version, and the fix version (the lowest version that clears every advisory)
- the advisory IDs
- the severity and the SLA due date
- the branch name, `fix/<package>-sla-<issue number>`
- whether the fix crosses a major version, and what that permits
