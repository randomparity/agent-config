# Tracker-Agnostic Issue Pipeline

Design for issue #4 — one shared workflow that drives either GitHub Issues or
Jira, rather than a parallel fork of every command.

## Context

Twelve files under `content/skills/` reference `github-tracking`, and the
pipeline they form (`/issue`, `/epic`, `/triage-issues`, `/work-issue`,
`/campaign`, `/ship-pr`, `/merge-cleanup`, `/recover-orphans`, `/retro`,
`/groom`) assumes GitHub throughout: `gh` invocations inline in prose, issue
references written `#N`, and pipeline state carried in `status:` labels.

Issue #4's body proposes splitting `/issue` into `/issue-github` and
`/issue-jira`. Applied across the pipeline that yields roughly twenty skills
whose logic is duplicated and drifts independently. The operator has since
clarified the goal: a shared workflow that can use either tracker, with the
label taxonomy adjustable if that helps, since the repo is new and lightly
used.

## Goals

- One implementation of pipeline logic, with tracker differences isolated
  behind a contract.
- Adding a third tracker later means writing one profile, not editing ten
  skills.
- The GitHub path's observable behavior does not change.
- Verification keeps its exit-code gate on both trackers — `just verify` must
  still be able to prove the tracker layer works.

## Non-goals

- **Pull requests stay GitHub-only**, assuming code hosting stays GitHub
  wherever issues live (ADR 0021 records this as an assumption with an explicit
  falsifier, not a fact). `/ship-pr`, `/merge-cleanup`'s PR half, and every PR
  operation remain `gh`. Only issue and epic tracking is pluggable. This
  roughly halves the affected surface.
- No migration tooling for moving existing issues between trackers.
- No simultaneous dual-tracker operation. One tracker is active per repo.

## Assumptions

Written here to be rejected rather than discovered. Dispatched design: no
operator was interviewed for these.

1. **A repo uses one tracker at a time**, declared in config. Mixed-tracker
   repos are out of scope.
2. **Jira access is via a scoped API token** in `ATLASSIAN_MCP_BASIC_AUTH`
   (`base64(email:token)`), the credential the Rovo MCP server already uses.
3. **Jira project type is not constrained.** The design must not assume
   team-managed or company-managed, because required fields and workflow
   statuses differ between them.
4. **Breaking the current GitHub conventions is acceptable** where it buys a
   shared design, per the operator's "we can adjust tags". Assumed to cover
   annotation-marker syntax and body-line conventions, not the `status:` value
   vocabulary, which encodes pipeline semantics.

## Verified facts

Established against a live Jira tenant (`randomparity.atlassian.net`, project
`SCRUM`, cloudId `53530fe5-674e-47fd-8f61-b8ef039b329f`) rather than assumed.
These are load-bearing; if one is wrong the design changes.

| Fact | Evidence |
|---|---|
| Jira labels accept `status:`-style colons | `status:triage` round-tripped intact on `SCRUM-1` |
| A scoped token drives the Jira REST API directly | `GET` 200, `PUT` 204, `POST` 201 against `api.atlassian.com/ex/jira/{cloudId}/rest/api/3` |
| Markdown converts to real rich content | `renderedFields` shows `<h2>`, `<ul>`, syntax-highlighted code |
| HTML comment markers render **visibly** in Jira | stored as `<p>&lt;!-- WORK:TRAJECTORY --&gt;</p>`; ADF has no comment node |
| Jira has native typed issue links | `blocks` / `is blocked by`, replacing the `Blocked by #N` prose grammar |
| No MCP tool can create a Jira status | all 43 tools enumerated; statuses are admin-UI configuration |
| A team-managed project's workflow may be tiny and unguarded | `SCRUM` has 4 statuses, every transition global and unconditional |

The REST result is the pivotal one: it means the tracker layer can be a tested
shell script with a real exit code, rather than verification degrading into
agent-loop judgment on the Jira side.

## Architecture

A tracker **engine** that deliberately lacks tracker knowledge, plus one
**profile** per tracker supplying it. This mirrors `check-records.sh` +
`profiles/{adr,debt}.sh`, already in this repo and already proven against two
record kinds.

```
content/skills/issue-tracking/
  SKILL.md                    conventions, tracker-neutral
  assets/
    tracker.sh                engine: dispatch, normalize, verify
    profiles/github.sh        gh-backed
    profiles/jira.sh          REST-backed
    tracker-test.sh           contract suite, runs against every profile
```

Skills invoke `tracker.sh <operation> …` instead of `gh issue …`. The engine
resolves the active profile, dispatches, and normalizes the result to one JSON
shape so callers never branch on tracker.

### What stays prose

The shim covers mechanical, verifiable operations. Judgment stays in the
skill: drafting issue bodies, ranking dedup candidates, assigning taxonomy
values. This is already how `/issue` splits — the agent drafts and judges,
`create-verified-issue.sh` performs and verifies the write — and the split
line does not move.

### Operation surface

Derived from actual call sites across the twelve skills.

| Operation | Used by |
|---|---|
| `create` (title, body, labels, parent) → id, url | `/issue`, `/epic` |
| `view` (id, fields) → normalized JSON | most |
| `search` (query, state) → ids | `/issue` dedup, `/campaign`, `/groom` |
| `label-edit` (id, add[], remove[]) | state machine writers |
| `label-ensure` (name, color, description) | `/triage-issues`, `/issue` |
| `comment-add` (id, body-file) | annotations |
| `comment-list` (id) → bodies | `/recover-orphans`, `/retro` |
| `state-set` (id, open\|closed) | `/merge-cleanup`, `/groom` |
| `link-parent` (child, parent) | `/epic`, `/issue` decompose |
| `link-blocks` (blocker, blocked) | `/issue` decompose |
| `label-history` (id, label) → timestamp | `/recover-orphans`, `/retro` |

`link-blocks` is where the abstraction pays immediately: GitHub needs the
`Blocked by #N` prose grammar and its ~90 lines of parsing in
`github-tracking`; Jira has a native typed link. Same operation, and the
GitHub-only parsing recipe stops being a convention every skill must know.

### Normalized issue shape

Every profile's `view` returns this, so callers never see tracker-native
fields:

```json
{
  "id": "4",  "ref": "#4",  "url": "…",
  "title": "…", "body": "…",
  "labels": ["status:ready"],
  "state": "open",  "done": false,
  "parent": null,   "updated": "2026-08-01T…Z"
}
```

`id` is tracker-native (`4`, `SCRUM-1`); `ref` is the form used in prose.
`done` is computed — GitHub closed-state, Jira `statusCategory == "done"` —
so no caller reimplements doneness.

## Decisions requiring records

Two, each with viable alternatives, each recorded as an ADR:

- **ADR 0021 — tracker abstraction shape.** Engine + profiles, rejecting the
  per-command fork from #4's body and a prose-only adapter.
- **ADR 0022 — canonical pipeline state.** `status:` labels remain
  authoritative on both trackers; Jira's native status is a write-only derived
  projection. Rejects native-workflow-authoritative (no way to provision
  statuses) and labels-only (Jira boards read as broken).

## Convention changes

Consequences of sharing, called out because they change GitHub behavior:

1. **Annotation markers become visible.** `<!-- WORK:TRAJECTORY -->` renders as
   literal text in Jira. Rather than keep a marker that is invisible on one
   tracker and noise on the other, annotations become a heading block
   (`## WORK:TRAJECTORY` … `## TRAJECTORY:COMPLETE`) on both. The
   whole-line-anchored matching and latest-complete-wins rules are unchanged;
   only invisibility is lost, and it was always cosmetic.
2. **`Blocked by #N` prose is replaced by `link-blocks`.** On GitHub the
   profile still writes and parses the body line; callers stop knowing that.
3. **`github-tracking` is renamed `issue-tracking`.** Twelve referencing files
   update in the same change. Per `CLAUDE.md`'s replace-don't-deprecate rule
   there is no alias.

## Decomposition

Too large for one PR. Issue #4 becomes an epic; each item below is one
PR-sized sub-issue, in dependency order.

| # | Sub-project | Delivers |
|---|---|---|
| 1 | **Adapter contract + GitHub profile** | `tracker.sh`, `profiles/github.sh`, contract test suite, wired into `just verify`. No skill changes, no behavior change. |
| 2 | **Tracker-neutral conventions** | `github-tracking` → `issue-tracking`; annotation marker change; blocked-by moves behind the contract. |
| 3 | **Tracker detection** | `/preflight` resolves the active tracker from repo config and reports it. |
| 4 | **Jira profile** | `profiles/jira.sh` against the same contract suite. |
| 5 | **Filing skills** | `/issue`, `/epic`, `/triage-issues` migrate to the contract. |
| 6 | **Pipeline skills** | `/work-issue`, `/campaign`, `/recover-orphans`, `/groom`, `/retro`, `/merge-cleanup` migrate. |

Ordering rationale: 1 establishes and proves the seam with zero behavior
change, so it is independently mergeable and reviewable. 4 lands only after 1
and 2 fix the contract, so the Jira profile is written against a settled
target rather than a moving one. 5 and 6 are mechanical once 1–4 hold.

## Sub-project 1 — detailed scope

The only sub-project this design specifies for implementation now.

### Deliverables

- `content/skills/issue-tracking/assets/tracker.sh` — engine implementing the
  eleven operations, dispatching to a profile resolved per ADR 0021: the repo's
  declaration is the source, `ISSUE_TRACKER` is an explicit override only.
- `content/skills/issue-tracking/assets/profiles/github.sh` — `gh`-backed
  implementation.
- `content/skills/issue-tracking/assets/tracker-test.sh` — contract suite,
  parameterized by profile, run by `just verify`.
- `create-verified-issue.sh` refactored to call `tracker.sh create` + `view`,
  preserving its current assertions and exit codes.
- `Justfile`: `tracker-test.sh` added to `test`; new scripts added to `lint`
  and `format-check`.

### Explicitly out of scope

No Jira profile, no skill prose changes, no rename, no `/preflight` work.
Those are sub-projects 2–6.

### Acceptance criteria

1. `just verify` passes.
2. `create-verified-issue-test.sh` passes unmodified — proving the refactor
   preserved behavior. This is the primary regression signal.
3. `tracker-test.sh` exercises every operation in the surface table against
   `profiles/github.sh` and fails if any is unimplemented.
4. A repo with no tracker declaration resolves to `github`, preserving today's
   behavior — that is what every repo is today. Any declaration or override
   naming a tracker with no profile fails with an actionable message giving the
   value and the profiles that exist, never a silent fallback to GitHub, which
   would run a write against the wrong tracker. Sub-project 1 ships the
   resolution rule; sub-project 3 supplies the declaration `/preflight` reads,
   so there is one mechanism throughout rather than an env var retrofitted
   later.
5. `shellcheck` and `shfmt` clean, matching the two-space style the Justfile
   already applies to `.github/scripts/`.
6. No skill's observable behavior changes; `git diff` touches no `SKILL.md`.

### Testing strategy

The contract suite is the load-bearing new test. It must be able to run
without network access or a live tracker, so `gh` and `curl` are invoked
through a single indirection the suite can stub — the same technique
`create-verified-issue-test.sh` already uses. A test that only asserts
"function exists" is not a contract test; each operation asserts its
normalized output shape against a fixture.

Per `CLAUDE.md`'s "verify tests bite": each new assertion is confirmed by
breaking the implementation and observing the failure before the change is
committed.

## Risks

- **The normalized shape may not survive contact with Jira.** Sub-project 1
  fixes a contract with only one implementation, which is where interface
  mistakes hide. Mitigated by the verified-facts table above — the shape was
  drawn from real Jira responses, not guessed — and by sub-project 4 being
  allowed to amend the contract if it does not fit.
- **`label-history` is thin on Jira.** GitHub exposes a label timeline;
  Jira's changelog records status transitions, and label changes land in a
  generic history. If it cannot be made reliable, the honest outcome is that
  the operation reports `unknown` on Jira, which `github-tracking` already
  defines a behavior for (stale-unknown: do not act on age, surface for a
  human).
- **Twelve-file rename in sub-project 2** is a wide but mechanical diff;
  contained by landing it alone.
