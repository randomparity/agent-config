# 0013 — Groom closes stale issues through a recoverable lifecycle

## Status

Accepted (2026-08-01)

## Context

Correctly triaged work can remain quiet indefinitely. Reporting that fact merely restates
durable tracker state and never reduces the queue, while closing without notice can discard
work that is still wanted.

This record migrates predecessor ADR 0022 from `randomparity/claude-config`.

## Decision

`groom` uses a three-stage lifecycle. It first warns after the quiet threshold and records
the future close date. After a grace period with no later activity, it closes the item as
not planned while preserving a stale marker. Activity after the warning revives the item by
removing that marker and restarting the clock. The close phase measures the marker's age,
not a general update timestamp, and fails closed when that age is unavailable.

In-flight, blocked, human-diagnosis, parent-planning, and open-change-referenced items are
excluded.

The policy is tracker-neutral: warn, allow a grace period, close with durable recovery
markers, revive on activity, and exclude active or coordinating work. The GitHub adapter
uses `GROOM:STALE`, the `stale` label timeline, `stateReason: NOT_PLANNED`, `status:` labels,
epic parents, and open pull-request references. These encodings and REST mechanics are not
requirements on another tracker.

## Consequences

- Quiet queues gain a recoverable exit rather than growing without bound.
- Warning and grace thresholds are policy defaults that may need later tuning.
- The stale marker is lifecycle state, not decoration; manual removal intentionally resets
  the process.
- Tokens unable to create or update the marker must stop rather than close without state.

## Considered & rejected

- **Report stale items without changing them.** The tracker already contains that signal,
  so the queue never shrinks.
- **Return items to triage.** This discards valid classification and creates churn.
- **Lower priority repeatedly.** Aging work into invisibility is less recoverable than an
  explicit close.
- **Use only the last-updated timestamp.** The warning action updates it and continually
  postpones closure.
- **Close without warning or recovery markers.** That makes mistaken cleanup difficult to
  identify and undo.
