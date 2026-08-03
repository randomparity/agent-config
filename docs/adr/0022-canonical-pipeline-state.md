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

`status:` labels are the single source of truth for **in-flight** state on every
tracker, with the value vocabulary unchanged.

Jira's native status field then carries two unrelated things, and separating
them is the whole of this decision.

**In-flight state: a cosmetic mirror.** Written after each label transition so
boards read correctly, and best-effort throughout — a failed write does not fail
the transition, a project missing a mapped status skips it, and the next
transition re-drives it. The mirror also skips any status whose `statusCategory`
is `done`, however it is named: categories are admin-set per status, so a
project that files its review or staging status under Done would otherwise let a
write this decision calls cosmetic flip `done` to true for an issue that is
still in flight.

| `status:` label | Jira status |
|---|---|
| `needs-triage`, `ready` | To Do |
| `in-progress` | In Progress |
| `in-review`, `awaiting-merge` | In Review |
| `blocked`, `needs-human` | In Progress |
| `epic`-labeled (carries no `status:`) | no write, overriding every row above |

**Terminal state: the record itself, not a mirror of one.** GitHub keeps
doneness in closed state, independent of labels, which is why `github-tracking`
defines no `status:done`. Jira has no independent equivalent: `resolution` is a
real doneness field, but the same transition drives it — verified on the tenant,
where closing set `resolution` and `resolutiondate` and reopening cleared both.
So on Jira the close write *is* the doneness record, and it is not best-effort.
It fails the operation and reports, because nothing re-drives a terminal
transition and no other field would hold the outcome. Closing projects to Done;
reopening projects back to whatever the issue's current `status:` label maps to,
or To Do if it carries none. `done` reads `statusCategory == "done"`, stable
across project types where status and resolution names are not.

## Consequences

- The seven-state machine and its transition rules survive intact; skills need
  no per-tracker state logic.
- Jira boards stay meaningful without native status becoming a second writer
  for in-flight state.
- Every Jira state change costs a second write: best-effort for the mirror,
  blocking for the close.
- **Jira doneness depends on a write succeeding, where GitHub doneness does
  not** — on GitHub the tracker maintains that field, on Jira this pipeline
  does.
- **The Jira board cannot distinguish parked from active.** `blocked` and
  `needs-human` both project to In Progress, so a human reads the label, not
  the board, to tell a stalled issue from a moving one.
- **Jira epics get no status write at all** and stay wherever they were created.
  Their state derives from sub-issues, exactly as on GitHub, so an epic's board
  position carries no meaning on either tracker.
- A UI edit to the **mirror** is silently overwritten by the next transition.
  That is intended: a mirror that could be edited back would be a second source
  of truth.
- **The close write has no such protection.** A user dragging a closed issue out
  of Done falsifies the field the pipeline reads for `done`, and nothing
  re-drives a terminal transition to repair it. The pipeline cannot detect this;
  a human must.

## Considered & rejected

- **Native Jira workflow authoritative.** Rejected because the pipeline needs
  seven states, no tool can provision the missing ones, and the skill would
  fail on any project an operator had not hand-configured.
- **Labels only; ignore native status.** Rejected because dropping the
  projection does not remove the doneness problem, it only leaves it unsolved:
  with no native status written and no terminal label, a Jira issue would have
  no representable terminal state. The never-moving board is the visible cost;
  this is the disqualifying one.
- **A terminal `status:` label carrying doneness on every tracker.** This
  preserves the record's own thesis most faithfully and would dissolve the
  two-tier split, the blocking Done write, and the UI-edit residual above.
  Rejected because it forks the vocabulary from GitHub, where closed-state is
  independently authoritative and a `status:done` label would be a second,
  desynchronizable source of truth for the same fact — `github-tracking` omits
  that value deliberately. Adopting it later is a supersession of this record,
  not an amendment.
- **A reduced state vocabulary that both trackers express natively.** Rejected
  because the states with no Jira equivalent are the ones carrying the most
  operational meaning; collapsing `awaiting-merge` into `needs-human` is
  precisely the conflation `github-tracking` forbids.
- **Per-tracker state models, each idiomatic.** Rejected because it puts a
  branch in every skill that reads state, which is what ADR 0021 exists to
  prevent.
