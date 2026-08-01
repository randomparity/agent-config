# 0012 — Groom reviews stale deferrals in one draft pull request

## Status

Accepted (2026-08-01)

## Context

Open debt records carry review dates, but a recurring warning in verification output does
not ensure anyone re-evaluates them. Filing an issue per stale record would move ownership
away from the versioned record and produce duplicate tracking state.

This record migrates predecessor ADR 0021 from `randomparity/claude-config`.

## Decision

The deferral sweep is the exception to `groom`'s report-or-file behavior: it updates all
stale open debt records in one draft change for human review. Each update advances the
review date and records a dated re-evaluation in the mutable status section. The sweep
never declares a concern resolved; a reviewer must replace the proposed update with a
resolution when the evidence warrants it. A later run updates the existing open draft
rather than creating another.

The policy is tracker-neutral: the record remains authoritative, re-evaluation is proposed
as a reviewable version-control change, and resolution requires human judgment. The GitHub
adapter realizes that change as one draft pull request and reuses it on subsequent runs.
Branch names, pull-request APIs, and draft-state mechanics are adapter details.

## Consequences

- Deferral evidence remains beside the concern in repository history.
- The draft has a terminal review outcome without creating one issue per record.
- Advancing a date without meaningful re-evaluation remains detectable in review, not by a
  mechanical gate.
- `groom` needs branch and push authority for this sweep but never merges its proposal.

## Considered & rejected

- **File one issue per record.** Issues would become competing owners of durable concerns.
- **File one roll-up issue.** A recurring roll-up has no clear terminal state and keeps the
  evidence away from the record diff.
- **Report only in the session.** The warning would again disappear without review.
- **Resolve records automatically.** An unattended maintenance sweep cannot establish that
  a concern is discharged.
