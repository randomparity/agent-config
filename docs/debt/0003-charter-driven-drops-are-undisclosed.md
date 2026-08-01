# 0003 — Charter-driven drops are undisclosed

## Status

Open
review-by: 2026-11-01

## Concern

`content/skills/review-loop/SKILL.md` sends verified deferrals to `challenge` as
CHARTER exclusions. A reviewer may honor an exclusion by withholding the concern, but
`challenge` reports only findings and governing-ADR suppressions. Its compact result has no
channel or count for a charter-driven drop, so the loop cannot distinguish withholding
from a fixed concern or a changed reviewer judgment.

This applies to the canonical challenge and review-loop packages installed for Claude and
Codex, whose native workflow invocations carry the same review contract. IBM Bob receives
the package tree, but its native invocation transport is excluded until this repository
proves that it preserves the same argument and trailing-CHARTER interface. Other workflows
that neither emit nor consume charter exclusions are also excluded.

## Why deferred

A durable fix changes `challenge`'s JSON and compact-output contract, which review-loop and
external adopters may consume. That contract change needs design and compatibility review;
adding it while migrating records would exceed issue #11's documentation-only scope.

The 2026-11-01 review date is three months after this repository adopted the inherited
concern. That interval permits observing the target-native workflows while keeping a silent
review-disclosure gap on a near-term review cadence.

## Non-regression boundary

Review-loop must not rely on a concern's disappearance as evidence that it was resolved.
Its exclusions remain advisory, it expects owned deferrals to recur, cheaply reaffirms a
recurring owned concern, and treats a finding that stops recurring as unproven. A future
change that makes convergence or approval depend on reviewer silence makes this debt
blocking.

## What would resolve it

Add a structured disclosure channel to `challenge` for charter-withheld concerns, including
the exclusion and owner, and expose its count in compact `--out` results. Update review-loop
to verify and report that channel. Resolution requires tests proving that a withheld concern
is visible without opening the full artifact and that invocations without a charter retain
their existing output behavior across the applicable Claude and Codex projections.

## Provenance

target: content/skills/challenge/SKILL.md
target: content/skills/review-loop/SKILL.md

Migrated for issue #11 from the predecessor repository's [debt 0002][predecessor] on
2026-08-01. The predecessor's command paths, issue references, and ADR numbering are
historical provenance only; they do not identify owners or resolutions here.

[predecessor]: https://github.com/randomparity/claude-config/blob/main/docs/debt/0002-charter-driven-drops-are-undisclosed.md
