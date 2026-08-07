# Centralize skill state under `.agent/`

## Problem

Canonical skills create working-tree state in directories named after one agent or
one toolkit. `campaign` writes its manifest to `.codex/campaigns/<slug>.md` even
when the running agent is Claude Code or Bob; `subagent-driven-development` and
`brainstorming` write to `.superpowers/`. The canonical set is agent-neutral by
construction (ADR 0001, ADR 0004), so a path that names a single agent is wrong
in every projection except one.

A second defect sits underneath the first. `campaign`, `subagent-driven-development`
and `codex-fleet` each instruct the agent to add their state path to
`.git/info/exclude`. That write is **denied** by Codex's `workspace-write` sandbox,
which treats `.git/` as a protected path. `campaign/SKILL.md` then says to "stop
with that as a named blocker" when the path is still not ignored — so `/campaign`
hard-stops under Codex, in the skill whose state directory is named `.codex/`.

## Evidence

Probed against Codex CLI 0.146.0, seatbelt sandbox, `sandbox_mode=workspace-write`,
in a throwaway repository:

| Target | Result |
|---|---|
| `.git/agent-state/` | `mkdir: Operation not permitted` |
| `.git/info/exclude` | `Operation not permitted` |
| `$HOME/.local/state/...` | `mkdir: Operation not permitted` |
| working-tree dir + self-ignoring `.gitignore` | wrote OK; absent from `git status` |

The last row was checked in both directions in one run: a directory written with
`printf '*\n' > .gitignore` did not appear in `git status --porcelain`, while a
sibling written without one appeared as `??`. `git check-ignore -q` confirmed the
first.

This rules out `.git/` and any `$HOME`-rooted location as the destination. Only a
working-tree directory is writable by every agent this repository targets.

The constraint was already known to one script — `sdd-workspace`'s header comment
states it — but recorded nowhere else, which is how three skills came to depend on
a denied write. ADR 0027 records it.

## Decision

State moves to `.agent/`, a working-tree directory whose name refers to no
particular agent or toolkit.

```
.agent/
├── .gitignore          # contains only: *
├── campaigns/          # root: $(git rev-parse --git-common-dir)/..  → shared
├── sdd/                # root: $(git rev-parse --show-toplevel)      → per-worktree
└── brainstorm/         # root: caller's --project-dir                → per-invocation
```

### Worktree resolution is split, because the two lifetimes differ

A campaign manifest must span the worktrees it dispatches into. `campaign` runs
waves of up to five worktree-isolated subagents, the orchestrator is its only
writer, and a resume has to reattach to the same manifest from wherever it is
resumed. It therefore resolves against `$(git rev-parse --git-common-dir)/..`,
which yields the main repository root from inside any linked worktree — the idiom
`finishing-a-development-branch/SKILL.md:118` already uses.

SDD artifacts belong to one branch's work. Five parallel campaign subagents each
running SDD would collide on a shared `progress.md`, so `sdd-workspace` keeps
`$(git rev-parse --show-toplevel)`, preserving today's behaviour.

`brainstorm` resolves no git root and gains none. `start-server.sh` takes a
`--project-dir` from its caller and appends the state path to it, falling back to
`/tmp` when the flag is absent. Its change is a path-segment rename only. It does
gain the `.gitignore` write, below.

### `brainstorm` writes the ignore file instead of asking the user to

`visual-companion.md` currently tells the agent to "remind the user to add
`.superpowers/` to `.gitignore`" — a tracked-file edit, performed by a human, in
whatever repository the session runs against. `start-server.sh` writes
`.agent/.gitignore` itself, on the same self-ignoring rule as every other consumer,
and the reminder is removed. A reminder is not a mechanism.

### The self-ignoring `.gitignore` replaces the `.git/info/exclude` step

It is not added alongside it. Keeping both would leave one working mechanism and
one that is denied under Codex, which is the defect this change exists to remove.
A `.gitignore` containing `*` ignores the directory's whole contents including
itself, needs no edit to any tracked file, and works in an arbitrary target
repository regardless of what that repository's own `.gitignore` tracks.

`campaign`'s `git check-ignore -q` verification stays. It is cheap and it is the
thing that catches a future regression in this mechanism.

## Scope

In scope — state these skills choose to create:

| File | Change |
|---|---|
| `campaign/SKILL.md` | `.codex/campaigns/` → `.agent/campaigns/`; drop the `.git/info/exclude` step |
| `subagent-driven-development/scripts/sdd-workspace` | `.superpowers/sdd` → `.agent/sdd`; rewrite the rationale comment |
| `subagent-driven-development/scripts/task-brief` | default-path comment |
| `subagent-driven-development/scripts/review-package` | default-path comment |
| `subagent-driven-development/SKILL.md` | path; drop the `.git/info/exclude` fallback |
| `brainstorming/scripts/start-server.sh` | `.superpowers/brainstorm/` → `.agent/brainstorm/` |
| `brainstorming/scripts/stop-server.sh` | comment |
| `brainstorming/visual-companion.md` | paths and the `.gitignore` reminder |
| `codex-fleet/SKILL.md` | replace `.git/info/exclude` advice with the self-ignoring pattern |

Out of scope, deliberately: the bare `.codex/` mentions in
`using-git-worktrees/SKILL.md`, `build-tdd/SKILL.md` and `work-issue/SKILL.md`.
Those state where Codex's *native worktree tool* places a worktree, which is a true
fact about that harness rather than a storage location this repository chooses.
Renaming them would make the documentation wrong.

Also out of scope: `brainstorming/scripts/server.cjs`'s `.codex-plugin/plugin.json`
probe, which is plugin discovery for a real Codex path, not state.

## Guard against recurrence

`scripts/check-skill-layout.sh` already rejects home-rooted agent paths with
`root_pattern='(~|[$]HOME|[$][{]HOME[}])/[.](codex|claude|bob)(/|$)'`. It has no
rule for repo-relative ones, which is the hole `.codex/campaigns/` used.

The extension rejects an agent-or-toolkit root **carrying a subpath**
(`.codex/x`, `.claude/x`, `.bob/x`, `.superpowers/x`) and permits a bare root. That
discriminator is not arbitrary: across the whole canonical set today, every
storage location carries a subpath and every legitimate reference is a bare root.
It needs no allowlist, so it cannot rot into a stale exemption.

`scripts/check-skill-layout-test.sh` gains a fixture for each arm — a subpath form
that must fail, and a bare form that must pass — so the discriminator is proven to
bite in both directions rather than only the one.

## This repository's own state

Three live manifests under `.codex/campaigns/` move to `.agent/campaigns/`. The
now-dead `.codex/campaigns/` line comes out of `.git/info/exclude`. The stale
`.superpowers/sdd/` directory is left for the user to remove or keep; it is not
this change's to delete.

## Verification

`just verify` — the full gate. It reaches `skills-check` (the extended layout gate),
`test` (which runs `check-skill-layout-test.sh` and both brainstorm server suites
that exercise the changed `start-server.sh`), `lint` and `format-check` over the
edited shell scripts, and `records` over the new ADR.

The brainstorm server suites are the functional arm: they start and stop the real
server, so a broken session-directory path fails them rather than passing a
text-only review.

## Non-goals

- No migration shim, dual-read fallback, or compatibility alias for the old paths.
  A skill reads one location.
- No change to what any manifest or brief *contains*, only where it lives.
- No new configuration knob for the directory name.
