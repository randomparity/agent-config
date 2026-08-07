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

Each row was produced by running, from the root of a throwaway git repository,
`codex sandbox -c sandbox_mode="workspace-write" -- bash -c '<probe>'` against Codex
CLI 0.146.0 on **macOS, seatbelt backend**. Linux, where Codex sandboxes with
Landlock/seccomp instead, was not probed.

| Probe | Result |
|---|---|
| `mkdir -p .git/agent-state` | `Operation not permitted` |
| `echo x >> .git/info/exclude` | `Operation not permitted` |
| `mkdir -p "$HOME/.local/state/agent-config/probe"` | `Operation not permitted` |
| `mkdir -p .superpowers/sdd` | wrote OK |
| `echo x > /tmp/probe` | wrote OK |
| `echo x > "$TMPDIR/probe"` | wrote OK |

The ignore mechanism was checked in both directions in one run: a directory written
with `printf '*\n' > .gitignore` did not appear in `git status --porcelain`, while a
sibling written without one appeared as `??`. `git check-ignore -q` confirmed the
first.

This rules out `.git/` and any `$HOME`-rooted location as the destination. Note the
last two rows: `/tmp` and `$TMPDIR` *are* writable and sit outside the workspace, so
the constraint is not a plain workspace boundary — `.git/` is denied by a protection
inside the workspace, `$HOME` by the confinement outside it. What that leaves is the
working tree as the only **durable** location writable by every agent this repository
targets; `/tmp` is writable but is exactly the ephemeral fallback `brainstorm` already
treats as lossy.

The constraint was already known to one script — `sdd-workspace`'s header comment
states it — but recorded nowhere else, which is how three skills came to depend on
a denied write. ADR 0027 records it.

## Decision

State moves to `.agent/`, a working-tree directory whose name refers to no
particular agent or toolkit.

```
.agent/
├── .gitignore          # contains only: *   — written by EVERY consumer, idempotently
├── campaigns/          # root: main repo root, absolutized  → shared
├── sdd/                # root: git rev-parse --show-toplevel → per-worktree
└── brainstorm/         # root: caller's --project-dir        → per-invocation
```

### Every consumer writes `.agent/.gitignore`, at the `.agent/` root

Not per-subdirectory, and not delegated to whichever skill happens to run first.
`sdd-workspace` today writes `$dir/.gitignore`, which under a naive rename becomes
`.agent/sdd/.gitignore` and leaves a sibling `.agent/campaigns/` uncovered. Since
`campaign` keeps its fail-closed `git check-ignore` verification, that ordering
decides whether a campaign runs at all: on a fresh clone where no `.gitignore` writer
has run, `git check-ignore -q .agent/campaigns/` returns 1 and `campaign` stops with a
named blocker — reproducing, by omission, the exact hard stop this change removes.

So each of `campaign`, `sdd-workspace` and `start-server.sh` performs
`printf '*\n' > .agent/.gitignore` before its first state write, on create and on
resume. It is idempotent, so ordering stops mattering.

### Worktree resolution is split, because the two lifetimes differ

A campaign manifest must span the worktrees it dispatches into. `campaign` runs
waves of up to five worktree-isolated subagents, the orchestrator is its only
writer, and a resume has to reattach to the same manifest from wherever it is
resumed. It therefore resolves against
`git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel`, which is the
idiom `finishing-a-development-branch/SKILL.md:118` uses.

The wrapper is not decoration. `git rev-parse --git-common-dir` returns an absolute
path only from a *linked* worktree; from the main worktree it returns `.git` at the
root and `../.git` from a subdirectory, so the bare `$(…)/..` form is the cwd-relative
literal `.git/..`. That is correct only while the process stays in the same directory,
and a manifest path is written into prompts, logs and resumes and read by subagents in
other worktrees. `git -C … rev-parse --show-toplevel` returns an absolute canonical
path from every cwd.

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

The extension rejects an agent-or-toolkit root **carrying a subpath** and permits a
bare root. It needs no allowlist, so it cannot rot into a stale exemption. Once this
change lands, every storage location the canonical set names carries a subpath and
every remaining mention is bare — an invariant this change establishes rather than
finds, since `stop-server.sh` and `visual-companion.md` today refer to storage with a
bare `.superpowers/`.

**"Bare" is decided by what follows the slash, and the prose is Markdown.** Every
legitimate mention is inside a code span, so the byte after the slash is a backtick.
A naive `[.](codex|claude|bob|superpowers)/[^[:space:]]` rejects all four. The
existing home-rooted rule sidesteps the analogous trap with its trailing `(/|$)`;
this one needs an explicit terminator set:

```
repo_pattern='[.](codex|claude|bob|superpowers)/[^[:space:]`,)"'"'"'.]'
```

A slash followed by a backtick, comma, close-paren, quote, period or whitespace ends a
bare root and passes. Anchoring the alternation on the slash is what keeps
`.codex-plugin/plugin.json` out of the rule — `.codex-plugin` is not `.codex/`, and it
is a real Codex plugin path in `brainstorming/scripts/server.cjs` that must keep
passing.

`scripts/check-skill-layout-test.sh` pins both directions with six fixtures:

| Fixture | Expected |
|---|---|
| ``under `.codex/`, a project-local`` (the worktree-prose form, ×1 of the 4 live sites) | pass |
| `` `.superpowers/` `` bare at end of a code span | pass |
| `.codex-plugin/plugin.json` | pass |
| `.codex/campaigns/<slug>.md` | **fail** |
| `.superpowers/sdd/progress.md` | **fail** |
| `~/.codex/skills` (the existing home-rooted arm) | **fail** |

The gate is then run against the real `content/skills/` tree, which is the only thing
that proves the four live worktree-prose sites still pass.

## This repository's own state

Three live manifests under `.codex/campaigns/` move to `.agent/campaigns/`.

The now-dead `.codex/campaigns/` line in `.git/info/exclude` is **operator work, not
agent work** — removing it is a write to `.git/`, the very write this change
establishes an agent cannot perform under Codex's sandbox. An agent implementing this
spec must not attempt it and stop on the denial it just documented. The line is inert
once nothing writes to `.codex/campaigns/`, so leaving it costs nothing.

The stale `.superpowers/sdd/` directory is left for the user to remove or keep; it is
not this change's to delete.

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
