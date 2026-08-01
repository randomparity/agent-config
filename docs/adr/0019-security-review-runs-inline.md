# 0019 — Security Review Runs Inline

## Status

Accepted (2026-08-01)

## Context

Not every branch changes a security boundary, but changes that do need focused analysis
before hand-off. Some agent clients also expose human-only security commands that a model
cannot invoke, so requiring those commands would make unattended workflow progress
impossible.

This records the final policy inherited from the predecessor's
[ADR 0023](https://github.com/randomparity/claude-config/blob/main/docs/adr/0023-security-stage-runs-inline-not-as-a-human-gate.md).

## Decision

During design, the workflow conditionally requires a threat model when the intended change
moves a security boundary. That model inventories boundaries and actors, names controls,
and states excluded threats; its controls become build criteria.

After adversarial review, the issue workflow applies the same trigger to the actual diff
and conditionally runs the repository's `threat-scan` skill. Findings are fixed, assigned
to the repository's verified durable owner, or—only at the bounded round-trip exit below—
reported unresolved at hand-off. A durable owner is a deferral record where supported,
otherwise a tracker issue.

The scan is an inline workflow stage, not a human approval gate. Its attention verdict is
work to disposition, not a reason by itself to park. Any human-only client command remains
an optional hand-off action and is never claimed as agent parity.

If a scan fix changes behavior, adversarial review covers that fix and the scan runs once
more. The workflow permits at most one such round trip. Findings that would require another
round are recorded as unresolved in the review summary and carried to hand-off rather than
restarting the loop or parking indefinitely.

## Consequences

Security analysis shapes the design before implementation and checks the resulting diff
where the boundary warrants its cost, without blocking all work on unavailable client UI
features. Claude, Codex, and Bob invoke the portable skill through their native mechanisms
only where installed; none claims it can trigger a human-only built-in. Scan evidence and
unresolved dispositions remain visible at hand-off.

## Considered & rejected

- **Run a threat scan on every branch.** Routine empty scans add cost and teach operators
  to ignore the stage.
- **Retain only the existing conditional security hedge.** A general instruction to apply
  security judgment produces no focused ship-path evidence or disposition contract.
- **Reuse adversarial review with security focus.** Focus text does not provide the distinct
  trust-boundary inventory and single-shot security verdict the hand-off needs.
- **Require a human-only security command.** Agents cannot reliably invoke client-side
  built-ins, so the workflow would deadlock.
- **Park on every attention verdict.** Findings require disposition, but the verdict alone
  does not establish an external blocker.
