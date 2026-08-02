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
| Jira has a `resolution` field distinct from status | present on `SCRUM-1` (null), one resolution defined site-wide; the Done transition sets `resolution` **and** `resolutiondate` on `SCRUM-2`. It is driven by the status write, so it does not make doneness independent of it |
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
content/skills/issue-tracking/          (named issue-tracking only from sub-project 2)
  SKILL.md                    conventions, tracker-neutral
  assets/
    tracker.sh                engine: dispatch, normalize, verify
    profiles/github.sh        gh-backed
    profiles/jira.sh          REST-backed
    tracker-test.sh           contract suite, runs against every profile
```

**Placement, and why it is not `issue-tracking/` yet.**
`scripts/check-skill-layout.sh` walks every child directory of `content/skills`
and fails with `required regular file is missing` when `<skill>/SKILL.md` is
absent, additionally requiring line 2 to read exactly `name: <dirname>`.
`skills-check` is a dependency of `just verify`. So creating
`content/skills/issue-tracking/assets/` in sub-project 1 would either turn the
gate red or force a second, near-duplicate tracking skill alongside
`github-tracking` — installed to every agent, since `install.sh` copies
`content/skills` wholesale, and therefore not the zero-observable-change slice
sub-project 1 is supposed to be.

Sub-project 1 therefore lands the assets under the **existing**
`content/skills/github-tracking/assets/`, where a conforming `SKILL.md` already
sits. Sub-project 2's rename carries the whole directory to `issue-tracking/`.

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
| `create` (title, **body-file**, labels, parent) → id, url | `/issue`, `/epic` |
| `view` (id, fields) → normalized JSON | most |
| `search` (**predicates**, state) → ids | `/issue` dedup, `/campaign`, `/groom` |
| `label-edit` (id, add[], remove[]) | state machine writers |
| `label-ensure` (name, color, description) | `/triage-issues`, `/issue` |
| `comment-add` (id, body-file) | annotations |
| `comment-list` (id) → bodies | `/recover-orphans`, `/retro` |
| `state-set` (id, open\|closed) | `/merge-cleanup`, `/groom` |
| `link-parent` (child, parent) | `/epic`, `/issue` decompose |
| `link-blocks` (blocker, blocked) | `/issue` decompose |
| `label-history` (id, label) → timestamp | `/recover-orphans`, `/retro` |

`create` takes a **body file**, not a string, matching `comment-add` and the
existing gated path — `create-verified-issue.sh` already requires a populated
temporary file and must keep doing so.

`search` takes **named predicates**, not an opaque query string. A query string
is tracker-native — GitHub qualifiers against JQL — so an opaque one would leave
the per-tracker branch in every calling skill, which is the outcome ADR 0021
rejects the writes-only shim to avoid. The predicates are what the call sites
actually use: `label`, `state`, `parent`, `text`, `updated-before`. Each profile
translates them. A call site that needs something outside this set is a signal
to extend it, not to add a raw escape hatch.

`label-edit` is a **delta** operation. It must not be implemented as a
read-modify-write of the full label set: the state machine's single-active-`status:`
invariant depends on add and remove applying as a delta, and a full-set write
races any concurrent labeller. Removing a label the issue does not carry is a
success, not an error.

`link-blocks` is where the abstraction pays immediately: GitHub needs the
`Blocked by #N` prose grammar and its ~90 lines of parsing in
`github-tracking`; Jira has a native typed link. Same operation, and the
GitHub-only parsing recipe stops being a convention every skill must know.

### Failure contract

Success shapes alone would leave callers unable to distinguish outcomes they
must act on differently — `/recover-orphans` and `/groom` treating "issue does
not exist" as "auth expired" drives a wrong write against a live tracker. Every
operation therefore shares one exit taxonomy:

| Exit | Class | Meaning |
|---|---|---|
| 0 | success | normalized payload on stdout |
| 1 | usage | bad arguments; nothing was attempted |
| 2 | not-found | the tracker answered, the object is absent |
| 3 | auth | credential missing, expired, or insufficient |
| 4 | transport | network, timeout, or unparseable tracker response |
| 5 | partial | a write may have landed; identity emitted if observed |

On any non-zero exit the operation emits a JSON error object on stdout —
`{"error": "<class>", "message": "…", "partial": {…}}` — and leaves the
underlying command's raw combined output on stderr.

Exit 5 exists for the case `create-verified-issue.sh` already hardens: a create
that fails while still printing a resolvable URL. That script computes its
diagnostics from the create command's raw combined output and exit status, so
the engine passes both through unchanged rather than swallowing them. Losing
that distinction would regress the behavior the four most recent commits on
`main` were written to defend.

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

All paths under `content/skills/github-tracking/assets/`, per the placement note
above; sub-project 2's rename carries them.

- `tracker.sh` — engine implementing the eleven operations and the failure
  taxonomy, dispatching to a profile resolved per ADR 0021 from the repo's
  declaration alone. No environment variable participates.
- `profiles/github.sh` — `gh`-backed implementation, declaring each operation
  implemented or degraded to a named value per ADR 0021.
- `profiles/fixture.sh` — a stub profile that declares at least one operation
  degraded. `profiles/github.sh` will not, so without this the declaration
  mechanism ships untested.
- `tracker-test.sh` — contract suite, parameterized by profile, run by
  `just verify`.
- `create-verified-issue.sh` refactored to call `tracker.sh create` + `view`,
  preserving its current assertions, diagnostics and exit codes.
- `Justfile`: `tracker-test.sh` added to `test`; new scripts added to `lint`
  and `format-check`.

**Tracker declaration format.** A single line in `AGENTS.md` at the repository
root, matching `^issue-tracker: ([a-z0-9-]+)$`. The root is
`git rev-parse --show-toplevel` of the working directory — never the skill's own
checkout, which would resolve every consuming repo to this one. Absent file,
absent line, or no git root at all resolves to `github`. A line present but
malformed is an error, not an absence: silently treating a typo as "no
declaration" is the wrong-tracker write by another route.

### Explicitly out of scope

No Jira profile, no skill prose changes, no rename, no `/preflight` work.
Those are sub-projects 2–6.

### Acceptance criteria

1. `just verify` passes.
2. `create-verified-issue-test.sh` passes **unmodified** — proving the refactor
   preserved behavior. This is the primary regression signal, and it covers the
   two hardened diagnostics specifically: a create that exits non-zero while
   printing a resolvable URL reports `creation command failed with exit 1;
   creation was not retried` and issues zero `view` calls, and a create that
   succeeds with no URL reports `durable issue URL could not be resolved`.
3. `tracker-test.sh` reads each profile's per-operation declaration and asserts
   the declared behavior — not mere existence. An operation neither implemented
   nor declared degraded fails the gate. Exercised against both
   `profiles/github.sh` and `profiles/fixture.sh`.
4. Every operation's **failure** behavior is asserted, not only its success
   fixture: each exit class in the taxonomy is triggered and its exit code and
   JSON error payload checked, including exit 5 carrying partial identity.
5. Resolution: no `AGENTS.md`, no matching line, or no git root resolves to
   `github`. A line naming a tracker with no profile fails with a message giving
   the value and the profiles that exist. A malformed line fails rather than
   resolving to `github`. All three are tested against fixture repos in
   sub-project 1, not deferred to sub-project 3.
6. `tracker-test.sh` passes with **no credentials present and no network
   reachable** — verified by unsetting `GH_TOKEN`/`GITHUB_TOKEN` and
   `ATLASSIAN_MCP_BASIC_AUTH` and asserting exit zero. Stubbing is by `PATH`
   interposition of a fixture `bin`, the technique
   `create-verified-issue-test.sh` already uses.
7. `label-edit` issues a delta call, asserted by the suite against the recorded
   `gh` invocation — not a full-label-set write. Removing an absent label exits
   zero.
8. `shellcheck` and `shfmt` clean, matching the two-space style the Justfile
   already applies to `.github/scripts/`.
9. No skill's observable behavior changes, and `git diff` touches no `SKILL.md`.
   Both hold because the assets land under the existing `github-tracking/`
   skill, which already has a conforming `SKILL.md`.

### Testing strategy

The contract suite is the load-bearing new test. It runs with no network and no
live tracker: `gh` and `curl` are reached through a single indirection the suite
stubs by `PATH` interposition of a fixture `bin`, the technique
`create-verified-issue-test.sh` already uses. Hermeticity is acceptance
criterion 6, not just an aspiration — a suite that quietly starts needing a
credential is one that stops running in CI.

A test that only asserts "function exists" is not a contract test. Each
operation asserts its normalized output shape against a fixture on success, its
exit code and error payload on each failure class, and — where the operation's
wire form carries an invariant, as `label-edit`'s delta does — the invocation
the profile actually issues.

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
