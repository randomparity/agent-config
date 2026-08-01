# 0007 — Governed Small Changes May Skip Pre-Code Design

## Status

Proposed

## Context

`$work-issue` currently treats every public-contract change as non-trivial and requires a
new specification, implementation plan, and their adversarial reviews before the first
failing test. That cost is appropriate when design authority is unsettled, but duplicates
work when an accepted decision already governs a small change and the issue supplies
explicit, testable acceptance criteria.

The abbreviated path must remain fail-closed: neither an issue author nor a campaign may
use a label alone to bypass design when implementation would make a new decision.

## Decision

Add `governed-small-change` as a third `$work-issue` classification. It is eligible only
when a linked accepted decision governs every changed contract and normative behavior in
scope, acceptance criteria are explicit and testable, no design-changing ambiguity remains,
and the work introduces no architecture, schema, dependency, persistence, concurrency,
authentication, migration, or external-service behavior.

The classification skips `$design` and proceeds from verified `WORK:SCOPE` to TDD. It does
not skip branch review, simplification, guardrails, PR creation, CI, or merge handoff. If
implementation discovers scope expansion or a new decision, work returns to the scope
checkpoint and full design rather than inferring authority. Campaign triage may preserve
the classification only with its governing-decision evidence and acceptance criteria.

## Consequences

- The first executable proof can precede optional design elaboration for settled changes.
- `$work-issue` and `$campaign` share an evidence-bearing classification contract.
- Deterministic fixtures must prove both eligibility and fail-closed fallback behavior.
- Operators still pay the full post-build review and shipping cost for every change.

## Considered & rejected

- **Keep the binary classification.** This preserves duplicate design work even when the
  decision is already accepted.
- **Add an eligibility predicate to the existing non-trivial class.** The predicate would
  still need an evidence-bearing identity that campaign dispatch can preserve; naming that
  identity as a classification makes the cross-workflow contract explicit.
- **Let callers request the short path directly.** A caller assertion is not evidence that
  design authority is settled and would make the bypass fail open.
- **Infer eligibility from labels or change size alone.** Neither proves that an accepted
  decision governs every changed contract or that ambiguity is absent.
