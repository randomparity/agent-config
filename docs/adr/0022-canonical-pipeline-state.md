# 0022 — Canonical Pipeline State Across Trackers

## Status

Accepted (2026-08-01)

## Context

The `github-tracking` skill carries pipeline state in a single-active
`status:` label per issue, over seven values: `needs-triage`, `ready`,
`in-progress`, `in-review`, `awaiting-merge`, `blocked`, `needs-human`. Closed
state is separately authoritative for doneness, so a closed issue is done
regardless of a lingering label.

Jira has a native workflow, which invites using it as the state machine
instead. Testing against a live team-managed project found the fit poor:

- Its workflow has four statuses (To Do, In Progress, In Review, Done) against
  the seven the pipeline distinguishes. `needs-triage` and `ready` collapse
  together, and `awaiting-merge`, `blocked`, and `needs-human` have no native
  home — including the `awaiting-merge` / `needs-human` distinction the skill
  calls out explicitly, one needing zero diagnosis and the other needing a
  human.
- None of the Rovo MCP server's 43 tools can create a status. Statuses are
  admin-UI configuration, so a skill cannot self-provision them the way
  `ensure_label` provisions labels.
- Every transition in that project is global and unconditional, so native
  workflow buys no ordering enforcement either.

Jira labels were confirmed to accept the existing vocabulary unchanged:
`status:triage` round-tripped intact, and JQL matches it without the
percent-encoding defect that afflicts `gh issue list --label`.

## Decision

`status:` labels remain the single source of truth on every tracker, with the
value vocabulary unchanged.

On Jira, native status is additionally written as a derived projection —
`needs-triage`/`ready` → To Do, `in-progress` → In Progress,
`in-review`/`awaiting-merge` → In Review, done → Done — so boards read
correctly to humans. It is never read back and never consulted for a decision.

Doneness is computed by the tracker profile and exposed as one normalized
`done` field: GitHub closed-state, Jira `statusCategory == "done"`. No caller
reimplements it.

A profile whose project lacks a status needed for the projection skips the
projection write and continues; the label is authoritative, so a missing
mirror is cosmetic.

## Consequences

- The seven-state machine and its transition rules survive intact; skills need
  no per-tracker state logic.
- Jira boards stay meaningful without native status becoming a second writer.
- Every Jira state change costs a second write. It is best-effort: a failed
  projection does not fail the transition.
- Native status can be edited in the Jira UI and will be silently overwritten
  by the next transition. This is intended — a mirror that could be edited
  back would be a second source of truth.
- Doneness on Jira depends on `statusCategory`, which is stable across project
  types, rather than on status names, which are not.

## Considered & rejected

- **Native Jira workflow authoritative.** Rejected because the pipeline needs
  seven states, no tool can provision the missing ones, and the skill would
  fail on any project an operator had not hand-configured.
- **Labels only; ignore native status.** Rejected because every issue sits in
  To Do forever, and a Jira board that never moves reads as a broken
  integration to anyone using the UI. The cost avoided is one write.
- **A reduced state vocabulary that both trackers express natively.** Rejected
  because the states with no Jira equivalent are the ones carrying the most
  operational meaning; collapsing `awaiting-merge` into `needs-human` is
  precisely the conflation `github-tracking` forbids.
- **Per-tracker state models, each idiomatic.** Rejected because it puts a
  branch in every skill that reads state, which is what ADR 0021 exists to
  prevent.
