# 0016 — Charters Bound Finding Ownership

## Status

Accepted (2026-08-01)

## Context

An adversarial loop can discover real defects adjacent to its requested change. Owning
every discovery causes scope growth, while ignoring all adjacent findings loses useful
evidence. The review target cannot decide its own permitted surface.

This records the final policy inherited from the predecessor's
[ADR 0007](https://github.com/randomparity/claude-config/blob/main/docs/adr/0007-review-loop-charter-bounds-finding-ownership.md).

## Decision

Every loop receives an externally authorized charter containing outcome, completion
criteria, provenance, exclusions, permitted surface, ambiguities, and interaction mode.
The charter establishes ownership but remains focus text, never a review target.

In-charter findings are fixed with remedies no larger than the risk they remove.
Out-of-charter concerns are validly deferred only to a verified durable owner; changing
the charter requires the external authority to rescope it. Correctness-required work that
cannot be completed is blocked. Review permission alone never authorizes rescoping.

## Consequences

Material adjacent defects remain visible without silently expanding the implementation.
Deferral records preserve owned follow-up, and proportionality prevents a review fix from
becoming an unrelated redesign. Each agent uses its native dispatch syntax while carrying
the same charter fields; an agent lacking the workflow makes no parity claim.

## Considered & rejected

- **Fix every defensible finding.** This gives the reviewer unbounded product authority.
- **Drop every out-of-scope finding.** This discards evidence with no accountable owner.
- **Let the reviewed artifact define scope.** A target could authorize the guarantees by
  which it is judged.
