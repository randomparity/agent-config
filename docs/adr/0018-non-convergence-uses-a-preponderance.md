# 0018 — Non-Convergence Uses a Preponderance

## Status

Accepted (2026-08-01)

## Context

Iterative adversarial review needs a bounded exit when fixes generate further findings.
Stopping on any self-caused finding is too sensitive, while waiting for unanimous evidence
can let a loop oscillate until its hard cap without explaining why.

This records the final policy inherited from the predecessor's
[ADR 0013](https://github.com/randomparity/claude-config/blob/main/docs/adr/0013-non-convergence-exits-fire-on-a-preponderance.md).

## Decision

The loop measures whether at least half of a pass's material findings cite text introduced
by its own fixes during the current cycle. When that threshold is reached on two successive
passes, it exits for rescoping rather than starting another repair pass. Findings on an
authorized record that the loop is creating do not count as self-collisions; this
accounting exemption grants no authority to create or widen the record.

Independent limits still bound iterations and rescope cycles. A non-convergent exit
reports unresolved findings and does not present the run as approved.

A stable pass may instead exit as converged with deferrals when no finding is both new and
not a self-collision, and the preceding pass made no target change. This preserves the
requirement that a review pass observe the state that will ship. Proportional remedies may
record a consequence or an owned deferral, but never suppress a material finding.

## Consequences

One concentrated pass does not terminate useful review, while repeated fix-induced
oscillation ends before consuming the entire budget. The report preserves the reason and
remaining work. Agents may implement iteration through native subagents or commands, but
use the same accounting rule wherever the review loop exists.

## Considered & rejected

- **Exit on the first self-caused finding.** A single repair mistake is not evidence that
  the loop as a whole is diverging.
- **Require every new finding to be self-caused.** Mixed cycles can still be dominated by
  oscillation and would evade the exit.
- **Rely only on the iteration cap.** The cap bounds cost but hides the observed failure to
  converge.
- **Require an approve verdict despite owned deferrals.** A recurring, already-owned
  concern would consume the cap even after the target stabilized.
