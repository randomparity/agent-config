# 0027 — Skill State Lives in the Working Tree, Under an Agent-Neutral Name

## Status

Accepted (2026-08-07)

## Context

Canonical skills create scratch state: `campaign` keeps a manifest that is the single
source of truth for a run, `subagent-driven-development` keeps task briefs, implementer
reports and a progress ledger, `brainstorming` keeps mockup sessions. That state is
short-lived, must survive a session boundary so a resume can reattach, and must never
reach a commit or a PR diff.

Two properties of its location were decided ad hoc and disagreed with each other.

**The directory was named after an agent.** `campaign` wrote to `.codex/campaigns/`
and the other two to `.superpowers/`. ADR 0001 and ADR 0004 make the canonical set
agent-neutral — one body of content projected into Claude, Codex and Bob — so a path
naming one agent is wrong in every projection but one, and a path naming one toolkit
is wrong in all of them. The name is not cosmetic here: `campaign` runs against
arbitrary target repositories, and its own text notes that many of them *track*
`.codex/`, where the manifest would land in a per-issue PR diff or trip `$preflight`'s
dirty-tree stop.

**`.git/` was assumed writable by three skills and known to be unwritable by a
fourth.** `campaign`, `subagent-driven-development` and `codex-fleet` each instruct the
agent to add their state path to `.git/info/exclude`, on the sound reasoning that a
per-clone exclude needs no edit to a tracked file. Meanwhile `sdd-workspace`'s header
comment says the workspace deliberately avoids `.git/` "because Codex can treat .git/
as a protected path and deny agent writes there". Both cannot hold.

The comment holds. Each row below was produced by running, from the root of a
throwaway git repository, `codex sandbox -c sandbox_mode="workspace-write" -- bash -c
'<probe>'` against Codex CLI 0.146.0 on **macOS, seatbelt backend**:

| Probe | Result |
|---|---|
| `mkdir -p .git/agent-state` | `Operation not permitted` |
| `echo x >> .git/info/exclude` | `Operation not permitted` |
| `mkdir -p "$HOME/.local/state/agent-config/probe"` | `Operation not permitted` |
| `mkdir -p .superpowers/sdd` | wrote OK |
| `echo x > /tmp/probe` | wrote OK |
| `echo x > "$TMPDIR/probe"` | wrote OK |

**Linux, where Codex sandboxes with Landlock/seccomp rather than seatbelt, was not
probed.** The commands are recorded so the table can be re-run rather than retrusted,
which is the point of writing them down in a record that cannot be edited later.

The last two rows are why the confinement is not a simple workspace boundary: `/tmp`
and `$TMPDIR` are writable and sit outside the workspace — Codex's
`[sandbox_workspace_write]` table carries `exclude_slash_tmp` and
`exclude_tmpdir_env_var` keys precisely because they are writable by default. So
`.git/` is not denied by confinement: it is *inside* the workspace and subtracted from
the writable set by a separate rule.

How separate, exactly, was probed rather than assumed, because the obvious variation
is the first thing a reader will try:

| Probe (added to `-c sandbox_mode="workspace-write"`) | `echo x >> .git/info/exclude` |
|---|---|
| `-c 'sandbox_workspace_write.writable_roots=["<repo>/.git"]'` | wrote OK |
| `-c 'sandbox_workspace_write.writable_roots=["<repo>"]'` | `Operation not permitted` |

So the `.git/` subtraction is overridden by a `writable_roots` entry naming `.git`
itself, and not by one naming the workspace root or a parent. It is a default, not an
inviolable protection. That does not revive `.git/` as a destination — see the
rejection below — but the reason is that a skill cannot require the entry, not that
the entry would fail.

So the `.git/info/exclude` instruction is dead code under Codex's default sandbox, and
it fails in the worst available way: `campaign` follows it with a `git check-ignore`
verification and a "stop with that as a named blocker" on failure, which converts a
denied write into a hard stop of the whole campaign. The skill named `.codex/` is the
one that cannot run under Codex.

The `$HOME` row matters because it forecloses the other obvious escape. A state
directory outside the repository would be invisible to the repository by
construction, but it falls outside the confinement boundary and is denied — a
different mechanism from the `.git/` denial above, and one that a `writable_roots`
entry could lift.

That leaves the working tree as the only *durable* location writable by every agent
this repository targets — which is where the state already was. `/tmp` and `$TMPDIR`
are writable, as the table shows, but they are ephemeral, which is why `brainstorm`
treats `/tmp` as the fallback a session loses rather than as a home for state. The defect was never the
working tree; it was the name, and the ignore mechanism layered on top of it.

The mechanism that does work was also already present, in the one script whose comment
got the constraint right. `sdd-workspace` writes `printf '*\n' >"$dir/.gitignore"`: a
`.gitignore` containing `*` ignores the directory's whole contents including itself.
Checked in both directions in a single run, a directory written with one did not appear
in `git status --porcelain` while a sibling written without one appeared as `??`, and
`git check-ignore -q` confirmed the first. It needs no edit to any tracked file and is
independent of whatever the target repository's own `.gitignore` happens to track —
the same properties `.git/info/exclude` was chosen for, minus the denial.

## Decision

**Skill state lives in `.agent/` in the working tree**, and the directory is made
self-ignoring by a `.gitignore` containing `*` at its root. The name refers to no
agent and no toolkit.

**The ignore file sits at `.agent/`, never per-subdirectory, and every consumer writes
it.** Both halves are load-bearing. A per-subdirectory file — which is what
`sdd-workspace` writes today at `$dir/.gitignore` — leaves a sibling `.agent/campaigns/`
uncovered, so which skill happened to run first would decide whether the next one's
state is ignored. And because `campaign` keeps a fail-closed `git check-ignore`
verification, a consumer that creates its state directory without the ignore file stops
the run.

**Both the write and the verification are rooted at the skill's own root, never at
cwd.** The write is `printf '*\n' > "$root/.agent/.gitignore"` and the check is
`git -C "$root" check-ignore -q .agent/campaigns/`, where `$root` is that skill's row
in the table above. Idempotence holds per root, not globally, so an unrooted literal is
not a smaller version of this rule but a different one. From a linked worktree the
unrooted forms fail in opposite directions at once: the write lands at
`<worktree>/.agent/.gitignore` while the manifest is at `<main>/.agent/campaigns/`, and
`git check-ignore` handed an absolute path into the main worktree exits **128**
`outside repository` — which `campaign` reads as a failure and turns into a named
blocker, reproducing this record's opening defect by a new route. Rooted with `-C` the
same check exits 0. Both probed on git 2.50.1.

**The write is refused, not forced, when the path is tracked.** `.agent/` is a generic
name chosen for neutrality, and neutrality is what makes collision plausible: a target
repository may already track `.agent/.gitignore` for its own tooling. A truncating
redirect over it would modify a tracked file in someone else's repository — the exact
failure `.codex/` was abandoned for. So a consumer checks first and stops with a named
blocker rather than clobbering.

`.git/`, `$HOME`-rooted state directories, and any edit to `.git/info/exclude` are out
for the sandbox reason above; a tracked `.gitignore` edit is out because it modifies
the target repository.

**The root a skill resolves against is decided by whether its state spans worktrees.**

| State | Root | Why |
|---|---|---|
| `.agent/campaigns/` | `git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel` | shared across worktrees |
| `.agent/sdd/` | `git rev-parse --show-toplevel` | per-worktree |
| `.agent/brainstorm/` | the caller's `--project-dir` | resolves no git root, and gains none |

**The campaign root must be absolutized, not used raw.** `git rev-parse
--git-common-dir` returns an absolute path only from a *linked* worktree; from the
main worktree it returns the relative `.git` at the root and `../.git` from a
subdirectory. So the bare expression `$(git rev-parse --git-common-dir)/..` is the
cwd-relative literal `.git/..`, which is correct only while the process's directory is
unchanged — and a manifest path is written into prompts, logs and resumes, and read by
subagents running in other worktrees. Wrapping it in `git -C … rev-parse
--show-toplevel` yields an absolute canonical path from every cwd, which is what
`finishing-a-development-branch/SKILL.md:118` does with the same expression.

A campaign manifest spans the worktrees it dispatches into: `campaign` runs waves of
up to five worktree-isolated subagents, the orchestrator is the manifest's only writer,
and a resume must reattach to the same file from wherever it is resumed.
`--git-common-dir/..` yields the main repository root from inside any linked worktree,
which is the idiom `finishing-a-development-branch` already uses for the same purpose.
Resolving a manifest with `--show-toplevel` instead would silently fork a second
manifest the first time a campaign was resumed from a worktree, and a duplicate
manifest is a duplicate run.

SDD artifacts belong to one branch's work, and five parallel campaign subagents each
running SDD would collide on a shared `progress.md`. `sdd-workspace` keeps
`--show-toplevel`, which is what it already did.

`brainstorm` is listed for completeness rather than because it resolves anything:
`start-server.sh` appends its state path to a `--project-dir` supplied by the caller,
and falls back to `/tmp` when the flag is absent. Giving it a git-root rule of its own
would be inventing a dependency it does not have. It does adopt the self-ignoring
`.gitignore`, replacing a line in `visual-companion.md` that asked the *user* to add
the directory to a tracked `.gitignore` by hand — a reminder is not a mechanism, and
that one also modified the target repository.

The split is two rules where one would be simpler, and it is deliberate. A single
shared root would need a namespacing layer under `.agent/sdd/` to keep parallel runs
apart — reintroducing per-worktree isolation as a naming convention, less reliably than
the filesystem provides it for free. A single per-worktree root would break campaign
resume.

**The layout gate is extended to catch the class rather than the instance.**
`scripts/check-skill-layout.sh` already rejects home-rooted agent paths; it gains a
repo-relative rule that rejects an agent-or-toolkit root carrying a subpath
(`.codex/x`, `.claude/x`, `.bob/x`, `.superpowers/x`) and permits a bare root.

That discriminator is drawn from the content rather than imposed on it: once this
change lands, every storage location the canonical set names carries a subpath and
every remaining mention is a bare root. The qualification matters — today
`brainstorming/scripts/stop-server.sh` and `visual-companion.md` each refer to storage
with a *bare* `.superpowers/`, so the invariant is something this change establishes
rather than something it found. The legitimate mentions are real and must keep passing —
`using-git-worktrees`, `build-tdd` and `work-issue` each name bare `.codex/` as an
example of where a harness's *native worktree tool* nests a worktree, which is a true
fact about that harness — four mentions across those three files, `using-git-worktrees`
carrying two. A fifth bare mention must keep passing too: `campaign/SKILL.md`'s note
that many target repositories *track* `.codex/`, which survives untouched even though
the rest of that file is rewritten. The rule needs no allowlist, so it cannot rot into
an exemption outliving its reason.

**"Bare" is decided by what follows the slash, and prose is Markdown.** Every one of
those legitimate mentions is written in a code span, so the byte after the slash is a
backtick — a naive "root followed by any non-space" rejects all four. The existing
home-rooted rule avoids the analogous trap by ending in `(/|$)`; the repo-relative rule
needs the same care, treating a backtick, comma, close-paren, quote or end-of-line as
terminating a bare root. The alternation is also anchored on the slash, which is what
keeps `.codex-plugin/plugin.json` — a real Codex plugin path in
`brainstorming/scripts/server.cjs` — outside the rule rather than inside it by accident.
The spec carries the pattern and the fixtures that pin both directions.

## Consequences

- `/campaign` runs under Codex. The `.git/info/exclude` write it depended on was denied
  there, and the skill's own fail-closed check turned that denial into a named blocker.
- One directory holds every skill's scratch state, so a user has one thing to inspect
  or delete and one entry to recognise, instead of `.codex/` and `.superpowers/`.
- The ignore mechanism no longer touches anything outside `.agent/`, and nothing depends
  on the target repository's own `.gitignore` — which is what made the old approach
  fragile against repositories that track `.codex/`. No tracked file is modified,
  *because the write refuses when its own path is tracked*; without that guard the
  guarantee would not hold, since a repository is free to track `.agent/.gitignore`
  itself.
- The sandbox constraint is recorded where it can be found. It was previously a comment
  in one script, which is why three skills were written against a denied write.
- The gate's repo-relative rule constrains future canonical content: a skill that wants
  repo-relative state under an agent-named directory now fails `just verify` on the
  commit that adds it. A skill needing to *mention* such a path in prose keeps the bare
  form, which is the form the existing prose already uses.
- Two root-resolution rules exist where a reader might expect one. The table above is
  the whole of it, and each skill resolves its root in exactly one place —
  `sdd-workspace` for SDD, the manifest step for campaign — so the rules cannot drift
  apart within a skill.
- The probes pin behaviour of a specific Codex version's sandbox, not a documented
  interface. A future Codex that permitted `.git/` writes would not invalidate this
  decision: the working tree remains writable, the name remains agent-neutral, and the
  self-ignoring `.gitignore` remains independent of the target repository. It would only
  mean one rejected alternative had stopped being impossible.
- Nothing migrates. There is no dual-read fallback for `.codex/campaigns/` or
  `.superpowers/sdd/`, so an in-flight campaign resumed across this change starts a
  fresh manifest rather than reattaching. That cost is paid once, is visible when it
  happens, and is preferable to a compatibility path that two mechanisms would then
  have to keep agreeing on.

## Considered & rejected

- **`.git/agent-state/`**, the location originally proposed. Rejected because Codex's
  `workspace-write` sandbox denies it by default, and the only thing that lifts the
  denial is a `writable_roots` entry naming `.git` in the *user's* Codex config — which
  a skill running against arbitrary target repositories cannot require, and which is a
  sandbox widening no skill should be asking a user to make on its behalf. Note the
  precise ground: not that the write is impossible, but that making it possible is out
  of a skill's reach. It is otherwise attractive — invisible to whole-tree tooling,
  never committed, scoped to the clone — which is why the constraint is recorded here
  rather than left as a comment for the next person to rediscover.
- **A `$HOME`-rooted state directory** such as `~/.local/state/agent-config/<repo-hash>/`.
  Rejected for the same denial, and independently for locality: state would no longer
  travel with the worktree it describes, and a hash-keyed directory is hard to find when
  a run needs inspecting.
- **Keep `.superpowers/` and move only `campaigns/` into it.** Rejected: it fixes the
  agent-specific name by adopting a toolkit-specific one. `.superpowers/` names a
  particular skill collection, which is no more neutral in a projection to Bob than
  `.codex/` is.
- **Keep `.git/info/exclude` alongside the self-ignoring `.gitignore`.** Rejected under
  replace-don't-deprecate: it leaves one working mechanism and one denied mechanism for
  a single job, and the denied one carries a fail-closed stop. Two mechanisms for one
  job is the defect surface this change removes.
- **A single root for all state, namespaced by branch under `.agent/sdd/`.** Rejected:
  it rebuilds per-worktree isolation as a naming convention on top of a filesystem that
  already provides it, and gets it wrong the first time two branches share a name after
  a slash-to-dash flattening.
- **A blanket repo-relative ban on agent roots, bare or not.** Rejected: it fails the
  four worktree-placement mentions across three skills, which are factually correct and describe real
  harness behaviour. Making the gate green would mean deleting true statements from the
  documentation to satisfy a pattern.
- **An allowlist of files exempt from the repo-relative rule.** Rejected for the reason
  ADR 0026 gives for the same choice: an allowlist is an assertion written once that
  stays green after its justification is gone. The bare-root discriminator is recomputed
  from the text on every run.
- **A configuration knob for the directory name.** Rejected as speculative surface. No
  caller needs it, and a configurable state path is one more thing two skills can
  disagree about.
