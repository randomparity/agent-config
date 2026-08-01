# 0014 — Governing Decisions Bound Reviews

## Status

Accepted (2026-08-01)

## Context

Adversarial review should find defects in a change without repeatedly reopening choices
that the repository has already accepted. Treating every related decision as settled is
also unsafe: a decision introduced or accepted by the reviewed change could otherwise
shield itself from scrutiny.

This records the final policy inherited from the predecessor's
[ADR 0003](https://github.com/randomparity/claude-config/blob/main/docs/adr/0003-challenge-reads-governing-adrs.md).

## Decision

A review consults only accepted, pre-existing ADRs that plausibly govern its target.
Their decisions are settled ground, but their implementations remain reviewable. A
concern already answered by a governing record is suppressed with an auditable citation;
new facts or risks are reported as possible reasons to supersede that decision.

An ADR added, accepted, superseded, or directly targeted by the reviewed change is a
review target, not governing context. It is challenged on its own merits.

## Consequences

Reviews avoid repetitive design debate without allowing new decisions to self-authorize.
Suppression remains visible, and bounded ADR lookup cannot displace review of the target.
Claude, Codex, and Bob use their native skill invocation mechanisms, but apply the same
classification wherever the challenge workflow is installed.

## Considered & rejected

- **Ignore ADRs during review.** This repeatedly re-litigates settled trade-offs.
- **Treat every accepted ADR in the branch as governing.** A change could shield its own
  decision merely by labeling it accepted.
- **Suppress matching concerns silently.** A clean verdict would conceal what the ADR
  prevented the reviewer from reporting.
