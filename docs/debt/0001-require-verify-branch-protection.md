# 0001 — Require Verify through branch protection

## Status

> **Resolved by issue #16 enforcement proof** (2026-07-31)

## Concern

The repository owns a decision-record gate, but GitHub does not currently require the
`Verify` check before merging to `main`.

## Why deferred

Branch protection is external repository state and changing it needs explicit maintainer
authority beyond this code change.

## Non-regression boundary

CI continues to run the complete `just ci` entry point on every pull request, and
documentation describes the gate as advisory until the setting is verified.

## What would resolve it

Require the exact `Verify` check for `main` and demonstrate that a failing pull request
cannot merge without an authorized bypass.

## Provenance

target: .github/workflows/verify.yml
Found while adopting the root gate for issue #7 on 2026-07-31.
tracker: #16
