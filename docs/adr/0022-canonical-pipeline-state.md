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
| issue reopened | the status its current `status:` label maps to, or To Do |
| `epic`-labeled (carries no `status:`) | no projection write |

The `epic` row wins over every other, including `issue closed`: an epic's state
derives from its sub-issues on both trackers, so its board position carries no
meaning and nothing should write it.

Terminal state is the exception, and it is not cosmetic. GitHub carries
doneness in closed-state, a field independent of the label set, and
`github-tracking` therefore defines no `status:done` label. Jira does have a
distinct doneness field — `resolution`, which the Done transition populates
along with `resolutiondate`, verified on the tenant — but it is set *by* that
transition rather than independently, so it does not remove the dependence on
the write. On Jira the Done projection is therefore where doneness lives, and
the normalized `done` field reads it back through `statusCategory == "done"`,
which is stable across project types where resolution names are not.

That yields two tiers with different guarantees:

- **The four in-flight arms are cosmetic and best-effort.** A failed write does
  not fail the transition, and a project lacking a mapped status skips it. The
  label stays authoritative and the next transition re-drives the mirror.
- **The Done arm is authoritative and must succeed.** A failed close projection
  fails the operation and reports it. Nothing re-drives a terminal transition,
  and no other field records the outcome, so a silent failure here would leave
  `done` false permanently. The missing-status skip does not apply to it.

## Consequences

- The seven-state machine and its transition rules survive intact; skills need
  no per-tracker state logic.
- Jira boards stay meaningful without native status becoming a second writer
  for in-flight state.
- Every Jira state change costs a second write. Best-effort on the four
  in-flight arms; blocking on the Done arm.
- **Jira doneness depends on a write succeeding, where GitHub doneness does
  not** — on GitHub the tracker maintains that field, on Jira this pipeline
  does.
- **The Jira board cannot distinguish parked from active.** `blocked` and
  `needs-human` both project to In Progress, so a human reads the label, not
  the board, to tell a stalled issue from a moving one.
- **Jira epics get no projection** and stay in whatever status they were
  created in. Their state derives from sub-issues, exactly as on GitHub, so the
  board position of an epic carries no meaning on either tracker.
- Native status on the **four in-flight arms** can be edited in the Jira UI and
  will be silently overwritten by the next transition. This is intended — a
  mirror that could be edited back would be a second source of truth.
- **On the Done arm that protection does not exist.** A user dragging a closed
  issue out of Done falsifies the field the pipeline reads for `done`, and
  nothing re-drives a terminal transition to repair it. The pipeline cannot
  detect this; a human must.

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
