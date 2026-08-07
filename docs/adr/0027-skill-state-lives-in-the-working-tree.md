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

The comment holds. Probed against Codex CLI 0.146.0 under seatbelt with
`sandbox_mode=workspace-write`, in a throwaway repository:

| Target | Result |
|---|---|
| `.git/agent-state/` | `mkdir: Operation not permitted` |
| `.git/info/exclude` | `Operation not permitted` |
| `$HOME/.local/state/...` | `mkdir: Operation not permitted` |
| working-tree directory | wrote OK |

So the `.git/info/exclude` instruction is dead code under Codex's default sandbox, and
it fails in the worst available way: `campaign` follows it with a `git check-ignore`
verification and a "stop with that as a named blocker" on failure, which converts a
denied write into a hard stop of the whole campaign. The skill named `.codex/` is the
one that cannot run under Codex.

The `$HOME` row matters because it forecloses the other obvious escape. A state
directory outside the repository would be invisible to the repository by
construction, but `workspace-write` confines writes to the workspace, so it is denied
for the same reason `.git/` is.

That leaves the working tree as the only location writable by every agent this
repository targets — which is where the state already was. The defect was never the
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
agent and no toolkit. `.git/`, `$HOME`-rooted state directories, and any edit to
`.git/info/exclude` are out for the sandbox reason above; a tracked `.gitignore` edit
is out because it modifies the target repository.

**The root a skill resolves against is decided by whether its state spans worktrees.**

| State | Root | Why |
|---|---|---|
| `.agent/campaigns/` | `$(git rev-parse --git-common-dir)/..` | shared across worktrees |
| `.agent/sdd/` | `$(git rev-parse --show-toplevel)` | per-worktree |
| `.agent/brainstorm/` | the caller's `--project-dir` | resolves no git root, and gains none |

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

That discriminator is drawn from the content rather than imposed on it: across the
canonical set, every storage location carries a subpath and every legitimate mention is
a bare root. The legitimate mentions are real and must keep passing —
`using-git-worktrees`, `build-tdd` and `work-issue` each name bare `.codex/` as an
example of where a harness's *native worktree tool* nests a worktree, which is a true
fact about that harness. The rule needs no allowlist, so it cannot rot into an
exemption outliving its reason.

## Consequences

- `/campaign` runs under Codex. The `.git/info/exclude` write it depended on was denied
  there, and the skill's own fail-closed check turned that denial into a named blocker.
- One directory holds every skill's scratch state, so a user has one thing to inspect
  or delete and one entry to recognise, instead of `.codex/` and `.superpowers/`.
- The ignore mechanism no longer touches anything outside `.agent/`. No tracked file is
  modified in a target repository, and nothing depends on that repository's own
  `.gitignore` — which is what made the old approach fragile against repositories that
  track `.codex/`.
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

- **`.git/agent-state/`**, the location originally proposed. Rejected on evidence:
  Codex's `workspace-write` sandbox denies it, and denies `.git/info/exclude` with it.
  It is otherwise attractive — invisible to whole-tree tooling, never committed, scoped
  to the clone — which is precisely why the constraint is recorded here rather than
  left as a comment for the next person to rediscover.
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
  three worktree-placement mentions, which are factually correct and describe real
  harness behaviour. Making the gate green would mean deleting true statements from the
  documentation to satisfy a pattern.
- **An allowlist of files exempt from the repo-relative rule.** Rejected for the reason
  ADR 0026 gives for the same choice: an allowlist is an assertion written once that
  stays green after its justification is gone. The bare-root discriminator is recomputed
  from the text on every run.
- **A configuration knob for the directory name.** Rejected as speculative surface. No
  caller needs it, and a configurable state path is one more thing two skills can
  disagree about.
