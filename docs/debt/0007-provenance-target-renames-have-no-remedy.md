# 0007 — Provenance target renames have no record-format remedy

## Status

Open
review-by: 2026-11-01

## Concern

Debt-record provenance is append-only, while the debt profile warns separately for every
`target:` path that no longer exists. After a target moves, appending its replacement leaves
the stale warning active, but editing or removing the old line triggers the rewrite guard.
The current root and canonical asset copies therefore retain the format gap described by
[predecessor debt 0005](https://github.com/randomparity/claude-config/blob/main/docs/debt/0005-provenance-target-rename-has-no-remedy.md).

## Why deferred

A remedy changes the durable record format and every adopter's interpretation of provenance.
Candidates include an explicit target-supersession marker or a narrowly mutable target field;
choosing between them requires a separate architecture decision and migration design.
Re-evaluate by 2026-11-01, one quarter after migration, before more copied gates accumulate
records under the current format.

## Non-regression boundary

This migration does not weaken append-only provenance, suppress individual orphan warnings,
or add replacement targets that leave a permanent warning. Every new target in this change
names a current root or canonical asset path.

## What would resolve it

Define and document a general target-renaming representation, implement it in the engine and
debt profile, migrate affected records, and add a test proving a renamed target can stop
warning without `E-REWRITE` or loss of provenance history.

## Provenance

target: .github/scripts/check-records.sh
target: .github/scripts/profiles/debt.sh
target: content/skills/decision-records/assets/check-records.sh
target: content/skills/decision-records/assets/profiles/debt.sh
Reproduced against issue #12's current root gate on 2026-08-01 by composing the per-line
orphan check with append-only `## Provenance` enforcement.
