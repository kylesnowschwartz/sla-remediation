# 2. Demo findings are seeded, but the advisories are real

Status: accepted, 2026-09-02

## Context

The demo runs against a fork of Apache Superset. Superset keeps its pins current, so an unmodified fork only has one real finding (Flask 2.3.3), and it's the hardest one. A demo you can run more than once needs a known starting state with a few findings of different difficulty.

## Decision

`bin/demo-reset` downgrades a few pins in the fork's `requirements/base.txt` to versions with published advisories (the list is in `demo/seeds.yml`) and commits them with a message that says they're seeds. The scanner is stock `pip-audit`, so every finding it reports is a public advisory and every fix Devin makes is a real upgrade. The service doesn't know which findings were seeded and treats them like any other.
