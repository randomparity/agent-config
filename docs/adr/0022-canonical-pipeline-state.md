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

`status:` labels remain the single source of truth for **in-flight** state on
every tracker, with the value vocabulary unchanged.

On Jira, native status is additionally written as a derived projection:

| `status:` label | Jira status |
|---|---|
| `needs-triage`, `ready` | To Do |
| `in-progress` | In Progress |
| `in-review`, `awaiting-merge` | In Review |
| `blocked`, `needs-human` | In Progress |
| issue closed | Done |
| `epic`-labeled (carries no `status:`) | no projection write |

Terminal state is the exception, and it is not cosmetic. GitHub carries
doneness in closed-state, a field independent of the label set. Jira has no
such field, and `github-tracking` establishes there is no `status:done` label
to carry it. So on Jira the Done projection *is* where doneness lives, and the
normalized `done` field reads it back through `statusCategory == "done"`.

That yields two tiers with different guarantees:

- **The four in-flight arms are cosmetic and best-effort.** A failed write does
  not fail the transition, and a project lacking a mapped status skips it. The
  label stays authoritative and the next transition re-drives the mirror.
- **The Done arm is authoritative and must succeed.** A failed close projection
  fails the operation and reports it. Nothing re-drives a terminal transition,
  and no other field records the outcome, so a silent failure here would leave
  `done` false permanently. The missing-status skip does not apply to it.

Doneness is exposed as one normalized `done` field — GitHub closed-state, Jira
`statusCategory == "done"` — so no caller reimplements it.

## Consequences

- The seven-state machine and its transition rules survive intact; skills need
  no per-tracker state logic.
- Jira boards stay meaningful without native status becoming a second writer
  for in-flight state.
- Every Jira state change costs a second write. Best-effort on the four
  in-flight arms; blocking on the Done arm.
- **Jira doneness depends on a write succeeding, where GitHub doneness does
  not.** This is the asymmetry to remember when reading `done`: on GitHub it is
  a field the tracker maintains, on Jira it is a field this pipeline maintains.
- **The Jira board cannot distinguish parked from active.** `blocked` and
  `needs-human` both project to In Progress, so a human reads the label, not
  the board, to tell a stalled issue from a moving one. The alternative —
  leaving native status stale — misinforms in a way that is harder to notice.
- **Jira epics get no projection** and stay in whatever status they were
  created in. Their state derives from sub-issues, exactly as on GitHub, so the
  board position of an epic carries no meaning on either tracker.
- Native status can be edited in the Jira UI and will be silently overwritten
  by the next transition. This is intended — a mirror that could be edited
  back would be a second source of truth.
- Doneness on Jira reads `statusCategory`, which is stable across project
  types, rather than status names, which are not.

## Considered & rejected

- **Native Jira workflow authoritative.** Rejected because the pipeline needs
  seven states, no tool can provision the missing ones, and the skill would
  fail on any project an operator had not hand-configured.
- **Labels only; ignore native status.** Rejected because every issue sits in
  To Do forever, and a Jira board that never moves reads as a broken
  integration to anyone using the UI. This is the closest call of the four:
  what it avoids is not merely one extra write but the whole two-tier
  guarantee above — a blocking Done arm, a board that cannot show parked, and
  doneness that depends on a write. It loses because dropping the projection
  does not remove the doneness problem, it only leaves it unsolved: with no
  native status and no `status:done` label, a Jira issue would have no
  representable terminal state at all.
- **A reduced state vocabulary that both trackers express natively.** Rejected
  because the states with no Jira equivalent are the ones carrying the most
  operational meaning; collapsing `awaiting-merge` into `needs-human` is
  precisely the conflation `github-tracking` forbids.
- **Per-tracker state models, each idiomatic.** Rejected because it puts a
  branch in every skill that reads state, which is what ADR 0021 exists to
  prevent.
