# 0015 — Review Companion Decisions First

## Status

Accepted (2026-08-01)

## Context

A design may add a companion ADR and then ask reviewers to respect governing decisions
while reviewing its specification and plan. Unless the new ADR is reviewed first, that
sequence can turn an untested decision into a shield.

This records the final policy inherited from the predecessor's
[ADR 0004](https://github.com/randomparity/claude-config/blob/main/docs/adr/0004-design-reviews-companion-adr.md).

## Decision

Design work detects every ADR added or changed on its branch and adversarially reviews
each record directly before reviewing artifacts that rely on it. The ADR review challenges
the soundness, alternatives, consequences, and proportional size of the decision. It does
not receive instructions to respect that same ADR as settled ground.

Only after the companion decision passes may later specification and plan reviews treat
it as reviewed context. The changed-ADR set is derived from Git state, not memory.

## Consequences

A new decision cannot bootstrap its own authority. Designs with no changed ADR skip this
stage explicitly. Claude and Codex dispatch their native review-loop skill; Bob follows
the policy only where the corresponding design and review workflows are installed.

## Considered & rejected

- **Review only the specification and plan.** Their conclusions may already depend on an
  unsound companion decision.
- **Review the ADR after dependent artifacts.** This reverses the required evidence order.
- **Trust the caller's recollection of changed ADRs.** Resumed or compacted sessions can
  lose that state, while Git retains it.
