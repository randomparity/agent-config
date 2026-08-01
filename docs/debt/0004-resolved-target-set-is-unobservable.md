# 0004 — The resolved review target set is unobservable

## Status

Open
review-by: 2026-11-01

## Concern

`content/skills/challenge/SKILL.md` reports a verdict, findings, next steps, suppressions,
and a run identifier, but not the target set it actually resolved. A full branch review and
a silently narrowed review can therefore produce indistinguishable compact results. The
CHARTER stop rule makes several malformed inputs fail visibly, but it is a prompt-level
preventive rule rather than evidence that the requested target set was reviewed.

This applies to canonical challenge runs and review-loop callers installed for Claude and
Codex. IBM Bob is excluded until its native workflow invocation and structured-result path
are verified against the same contract. File-list, branch, and working-tree review modes
are included; workflows that do not consume challenge results are excluded.

## Why deferred

The direct fix adds structured target identity to a public output contract used by looping
callers and possible external adopters. A prose-only summary would be cheaper but would not
permit a mechanical comparison. Choosing and versioning that contract is separate from
record migration.

The 2026-11-01 review date is three months after target-repository adoption. The shorter
cadence reflects that an undetected target collapse can turn incomplete review into a clean
approval signal.

## Non-regression boundary

No caller may treat the CHARTER parsing boundary as proof that its requested targets were
resolved. Review-loop continues to derive artifact paths from requested target tokens,
requires a fresh matching run identifier, and treats missing artifacts and explicit target-
resolution errors as failures rather than approvals. A future merge or convergence decision
that assumes target-set equality makes this debt blocking.

## What would resolve it

Add the resolved file set, or an unambiguous branch/working-tree range identity, to
`challenge`'s structured artifact and expose a count or digest in the compact result. Update
review-loop to compare that identity with the requested target. Resolution requires tests
where a deliberately narrowed target fails the caller assertion while valid file-list,
branch, and working-tree runs pass for the applicable Claude and Codex projections.

## Provenance

target: content/skills/challenge/SKILL.md
target: content/skills/review-loop/SKILL.md

Migrated for issue #11 from the predecessor repository's [debt 0007][predecessor] on
2026-08-01. Predecessor-local paths, issues, and ADRs are evidence of origin, not target-
repository resolution claims.

[predecessor]: https://github.com/randomparity/claude-config/blob/main/docs/debt/0007-no-detection-for-a-collapsed-target-set.md
