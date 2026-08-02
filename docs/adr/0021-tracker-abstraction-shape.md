# 0021 — Tracker Abstraction Shape

## Status

Accepted (2026-08-01)

## Context

The issue pipeline in `content/skills/` assumes GitHub throughout: `gh`
invocations inline in skill prose, issue references written `#N`, and pipeline
state in `status:` labels. Twelve files reference the `github-tracking` skill.

Issue #4 asks for Jira as an alternative tracker and proposes splitting
`/issue` into `/issue-github` and `/issue-jira`. The operator has clarified
that the goal is a shared workflow across the whole pipeline rather than a
per-command split.

Skills are prose instructions an agent reads, not compiled code, so an
abstraction can live either in that prose or in a script the prose invokes.
The choice matters most for writes: `/issue` currently funnels issue creation
through `create-verified-issue.sh`, which creates, reads back, asserts, and
returns an exit code — a guarantee that only survives if the tracker layer is
also executable. A scoped Atlassian API token was confirmed to drive the Jira
REST API directly (`GET` 200, `PUT` 204, `POST` 201), so an executable layer is
available for both trackers.

## Decision

Introduce a tracker engine that deliberately lacks tracker knowledge, plus one
profile per tracker that supplies it, under
`content/skills/issue-tracking/assets/`: `tracker.sh` with
`profiles/github.sh` and, later, `profiles/jira.sh`.

Skills invoke `tracker.sh <operation>` rather than `gh issue`. The engine
resolves the active profile, dispatches, and normalizes results to one JSON
shape, so no caller branches on tracker. A contract test suite runs every
operation against every profile and is wired into `just verify`.

Resolution has **one** source: the repo's own declaration in its instruction
files. `ISSUE_TRACKER` is an explicit per-invocation override and nothing more.
A repo declaring nothing is a GitHub repo, which is what every repo is today. A
declaration naming a tracker with no profile is an actionable error and never a
fallback to GitHub — falling back would route a write into the wrong tracker,
and unlike `gh issue delete`, a live Jira tenant has no comparable undo.

Environment state is not the source. It is per-shell, invisible in a diff or a
resumed session, and absent by default, so in a Jira-tracked repo an unset
variable would be precisely that silent wrong-tracker write — reached by
omission rather than by typo, which is the likelier of the two.

This mirrors `check-records.sh` + `profiles/{adr,debt}.sh`, already in this
repo and already carrying two record kinds.

The split between script and prose does not move: mechanical, verifiable
operations go behind the contract; judgment — drafting bodies, ranking dedup
candidates, assigning taxonomy — stays in the skill.

Pull requests are out of scope, on the **assumption** that code hosting stays
GitHub wherever issues live. That assumption cuts more scope than any other
sentence here — roughly half the affected surface — and unlike this record's
other premises it is a claim about the operator rather than about a system, so
nothing verified it. Its falsifier is explicit: an adopter hosting code
elsewhere, plausibly Bitbucket alongside Jira, supersedes this record rather
than extending it.

## Consequences

- Adding a third tracker is one profile, not an edit to ten skills.
- `create-verified-issue.sh` keeps its exit-code gate on every tracker;
  verification does not degrade into agent-loop judgment.
- A contract suite can test the tracker layer with no network and no live
  tracker, so `just verify` covers it.
- The contract is fixed against one implementation first, which is where
  interface mistakes hide. The profile that lands second is permitted to amend
  it.
- Skill prose gains an indirection: a reader must consult the contract to know
  what a call does, where previously the `gh` invocation was literal.
- `github-tracking` becomes `issue-tracking`, updating every referencing file:
  twelve under `content/skills/`, plus `scripts/check-cleared-dependencies-test.sh`,
  which hardcodes the skill's path and breaks on the rename.

## Considered & rejected

- **Per-command fork (`/issue-github`, `/issue-jira`), as issue #4's body
  proposed.** Rejected because applied across the pipeline it yields roughly
  twenty skills duplicating logic that then drifts independently — the same
  duplication the repo already rejected for guardrail commands in ADR 0002.
- **Prose-only adapter: a reference doc mapping abstract operations to each
  tracker's commands, with the agent translating.** Rejected because it cannot
  return an exit code. `create-verified-issue.sh`'s read-back assertions would
  have no Jira equivalent, and recent work has been hardening exactly that
  path.
- **A writes-only shim: contract the mutating operations, leave reads in
  prose.** The exit-code argument above applies only to writes, so this buys the
  whole stated justification for roughly half the surface. Rejected because a
  read left in prose is still a read every skill performs in tracker-specific
  syntax — `gh issue view --json` against JQL — which reinstates the per-tracker
  branch in the ten skills this record exists to keep uniform. The asymmetry it
  identifies is real and survives in the design: reads are the operations
  permitted to degrade, as `label-history` may on Jira, where a write is not.
- **Route every tracker call through the Rovo MCP server.** Rejected because
  MCP tools cannot be invoked from a shell script, which forfeits the same
  exit-code guarantee, and it makes the GitHub path depend on an MCP server it
  does not need today.
- **Do nothing; keep the pipeline GitHub-only.** Rejected because it does not
  meet the issue, though it remains the correct outcome if Jira support is
  never exercised — the cost of this decision is a real indirection paid by
  every reader of the pipeline.
