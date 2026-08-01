# 0008 — Gate existence depends on known names or workflow references

## Status

Open
review-by: 2026-11-01

## Concern

The gate distinguishes first-time installation from an undeclared rename by looking for a
known gate basename in the running script's current directory at the base revision or in a
base-revision GitHub workflow. A non-GitHub CI adopter can install the script under an
unregistered name, then move and rename it in one change. Neither witness fires, so the gate
reports bootstrap instead of `E-GATE-EMPTY-SET`. This reproduces
[predecessor debt 0006](https://github.com/randomparity/claude-config/blob/main/docs/debt/0006-gate-existence-witnesses-miss-an-undeclared-move.md).

## Why deferred

A filename-, directory-, and CI-provider-independent witness needs an adopter-facing identity
or trusted fingerprint. A loose filename glob would create false failures for unrelated
checks, while an in-tree declaration shares the self-edit boundary tracked by debt 0006.
Re-evaluate by 2026-11-01, one quarter after migration, with evidence from non-GitHub adopters.

## Non-regression boundary

Retain both existing witnesses, the closed known-name registry, and the distinction between a
real first installation and a known undeclared rename. No change may make the bootstrap result
reachable in a repository shape where the current gate reports an error.

## What would resolve it

Record a provider-neutral gate identity that survives filename and directory changes without
matching unrelated checks. Add a regression fixture for an unknown base name, no GitHub
workflow, and a simultaneous move and rename; it must report `E-GATE-EMPTY-SET` and fail when
the new witness is removed.

## Provenance

target: .github/scripts/check-records.sh
target: .github/scripts/check-records-test.sh
target: content/skills/decision-records/assets/check-records.sh
target: content/skills/decision-records/assets/check-records-test.sh
Reproduced against issue #12's current root gate on 2026-08-01 from `gate_existed_at`'s known
basename and GitHub-workflow witnesses.
