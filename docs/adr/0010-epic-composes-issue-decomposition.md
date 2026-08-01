# 0010 — Epic planning composes issue decomposition

## Status

Accepted (2026-08-01)

## Context

The `epic` skill turns a feature idea into the dependency-ordered work set consumed by
`campaign`. The durable planning artifact, the boundary between planning and workable
items, and the ownership of tracker state must remain clear across tracker adapters.

This record migrates
[predecessor ADR 0002](https://github.com/randomparity/claude-config/blob/main/docs/adr/0002-epic-command-composes-issue-decompose.md).

## Decision

`epic` owns the interview and PRD, then composes `issue` decomposition rather than
reimplementing filing, deduplication, or triage. The parent is a planning holder and is
never directly workable; its state derives from single-level child issues. Children carry
their own readiness, unresolved-question, and ordering-dependency state, and `campaign`
operates on those children only. Creating the work set does not start execution.

The policy is tracker-neutral: one durable parent, durable parent-child relationships,
independently actionable children, and durable child lifecycle state. The GitHub adapter
stores the PRD in an `epic`-labelled issue body, uses native sub-issues, omits `status:` from
the parent, and represents an ordering dependency with `status:blocked` plus `Blocked by
#N`. Those names and API mechanics do not define the policy.

## Consequences

- Any session can resume from tracker state without a parallel planning store.
- Partial filing is recovered by rerunning decomposition and adopting existing children.
- Parent closure and campaign launch remain explicit operator actions.
- A future tracker adapter may encode the same roles differently without changing this
  decision.

## Considered & rejected

- **Make the parent directly workable.** This conflates planning state with child delivery
  state and gives the parent two lifecycle meanings.
- **Keep the PRD only in a repository document.** This creates a second artifact that can
  drift from the tracker hierarchy.
- **Start `campaign` automatically.** Filing and execution have different cost and authority
  boundaries.
- **Build decomposition into `epic`.** Duplicating issue creation and deduplication would
  create two mechanisms for the same job.
