---
name: clean-branches
description: "Sweep local branches whose work has landed: classify every local branch, delete the merged and squash-merged ones after one confirmation, remove their worktrees, and report every deletion and skip. Use when asked to clean merged or gone branches or prune stale local branch state."
---
# Clean Merged Branches

Repo-wide hygiene sweep for local branches whose work has landed. `$merge-cleanup` deletes
the one branch it just merged, in flow; this collects what that never sees — PRs merged in
the GitHub UI, by another session, or before this config existed. Read → plan → one
confirmation → apply.

**Success and no-op must be distinguishable in the output.** That is the whole point of this
command: the (since-disabled) `commit-commands` plugin's `/clean_gone` grepped `git branch -v` for `[gone]`, but
`-v` never prints tracking info and git's actual text is `[origin/<branch>: gone]`, so the
loop body never runs. It exits 0, prints nothing, deletes nothing — identical to a clean
repo. Do not use it. Every path below either names what it did or says plainly that nothing
matched.

## Steps

1. **Refresh tracking state.** `git remote get-url origin`, then `git fetch --prune`. Both the
   ancestry test and the `never pushed` row are claims about `refs/remotes/origin`, and a
   stale one is worthless. Check the remote explicitly: `git fetch --prune` exits **0** in a
   repo with no remotes and in one whose only remote is named something else, and the sweep
   would then read an empty remote-head set, call every branch `never pushed`, and report that
   as a fact. Stop and say so if there is no `origin` or the fetch fails (offline, auth) — do
   not evaluate a single branch against stale or absent state.
2. **Resolve the base branch.** `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`;
   without `gh`, `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/`.
   Every ancestry test below runs against `origin/<base>` — the ref you just fetched, not a
   local base that may be behind. **Stop if neither resolves** — the fallback exits 128
   whenever `origin/HEAD` was never set, and the base name is both the only thing protecting
   the base branch (row 1) and the reference for every ancestry test. Never guess `main`.
3. **Enumerate candidates** — every local branch — with plumbing, not porcelain:

   ```bash
   git for-each-ref --format='%(refname:short)%09%(upstream:short)%09%(upstream:track)' refs/heads
   ```

   Repo-wide on purpose. Filtering here on `%(upstream:track)` equal to `[gone]` found only
   branches whose upstream ref had been deleted, which made the `merged` and
   `squash-merged` rows below unreachable for the leftovers this sweep exists to collect: a
   branch created by `git worktree add <path> -b <branch> origin/<base>` tracks the *base*, so
   its track field reads empty until its first commit and `[ahead N, behind M]` after, and
   pushing it with `-u` only moves that to `[behind N]` or empty. A repo with
   `deleteBranchOnMerge: false` then keeps the remote head after the merge, so a pruned fetch
   cannot produce `[gone]` either. Both tracking fields are still read — the `never pushed`
   row needs them — but neither decides who gets looked at.

   Enumerating more does not delete more. Every branch runs the full classification below, and
   only `merged` and `squash-merged` delete.
4. **Read the remote heads, once**, for the `never pushed` row:

   ```bash
   git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin
   ```

   One command for the whole sweep; intersect names locally rather than probing per branch.
   `refs/remotes/origin/HEAD` contributes the name `HEAD`, which is harmless: git rejects
   `HEAD` as a branch name, so it can never match a local branch.
5. **List the protected branches**, once, for row 2:

   ```bash
   gh api "repos/{owner}/{repo}/branches?protected=true" --jq '.[].name'
   ```

   Without `gh` the set is unknown, not empty. Row 2 then cannot fire, so mark every `merged`
   line in the plan protection-unverified and read them before confirming; do not guess
   protection from branch names.
6. **Map worktrees.** `git worktree list --porcelain` — records separated by blank lines,
   each with a `worktree <path>` and, when a branch is checked out, `branch refs/heads/<name>`.
   A detached worktree emits `detached` instead and never enters the map. The first record is
   the main checkout, and nothing marks the *current* one — compare each `worktree <path>`
   against `git rev-parse --show-toplevel` to find it. Map branch → **set** of paths:
   `git worktree add --force` allows one branch in two worktrees, and a 1:1 map would let the
   plan promise one removal and then fail the deletion.
7. **Classify every candidate** (table below) before touching anything.
8. **Plan → confirm.** Present one table — `branch → classification → action` — including the
   skips and their reasons, and naming the path of every worktree the plan would remove. Take
   one explicit confirmation, then apply. A failure on one branch does not abort the sweep.

## Classification

Test each branch against these rows **in order; first match wins.** The order is load-bearing
now that enumeration is repo-wide: the base branch is an ancestor of `origin/<base>`, so an
unordered table would classify it `merged` and delete it.

| # | Candidate | Test | Action |
|---|---|---|---|
| 1 | base branch | name equals `<base>` | skip, name it |
| 2 | protected | name is in step 5's protected set | skip, name it |
| 3 | checked out where the sweep must not reach | branch is the HEAD of the main checkout, of the worktree the sweep is running in, or of more than one worktree | skip, name it |
| 4 | never pushed | neither push evidence holds: no `refs/remotes/origin/<branch>` in step 4's set, and no `%(upstream:track)` of `[gone]` whose `%(upstream:short)` is `origin/<branch>` | **skip, never delete** |
| 5 | dirty worktree | `git status --porcelain` in its worktree is non-empty | skip, name it |
| 6 | merged | `git merge-base --is-ancestor <branch> origin/<base>` succeeds | delete |
| 7 | squash-merged | not an ancestor, but `gh pr list --head <branch> --state merged --json number,title --limit 1` returns a PR | delete; the plan line names the PR |
| 8 | unmerged | neither — no ancestry, no merged PR (or no `gh`/GitHub remote) | **report, never delete** |

**Row 2 is new because enumeration is.** Under the old `[gone]` predicate a long-lived
integration branch was never a candidate. Now it is: merge `release/1.2` into the base with
`--no-ff` and leave it in place, and it is an ancestor of `origin/<base>` with a live remote
head — indistinguishable by any local test from a feature branch nobody cleaned up. The
remote's protection setting is the signal that tells them apart, so read it; where it cannot
be read, the confirmation is the last guard and the plan has to say so.

**Row 3** covers the sweep's own worktree because `git worktree remove` will happily remove the
directory you are standing in and leave you with no working directory. It covers a branch in
two worktrees because `git branch -d` refuses a branch checked out anywhere, so removing one
of the two paths destroys a directory and still cannot delete the branch.

**This sweep has no liveness signal, and enumeration is now repo-wide, so any *other* linked
worktree it reaches may belong to an agent that is still running.** A dispatched worker's
pull request merges some way before the worker itself stops, and in that window the branch is
an ancestor of the base and the worktree is live. Do not run the sweep while a campaign or a
dispatched worker is in flight. Row 5 catches only the workers that left tracked files behind.

**Never delete a never-pushed branch.** Row 4 states a rule that used to be an accident of
enumeration — a branch with no upstream yielded an empty track field and was never a
candidate. State it positively: a branch is deletable only on *evidence that it was pushed*,
never on the absence of evidence that it was not. That evidence is a remote head under the
branch's own name, or a `[gone]` track field naming a head that had the branch's own name; the
two cover both settings of `deleteBranchOnMerge`.

Both halves of the `[gone]` clause are load-bearing, because `[gone]` is a fact about
*whatever the branch tracks*, not about the branch. `git switch -c mine origin/theirs` sets
the upstream to a colleague's branch and pushes nothing; when their pull request merges and
GitHub deletes their head, `mine` reads `[gone]` while `refs/remotes/origin/mine` never
existed — and `mine` is now an ancestor of the base. Unscoped, the clause would delete it.
Scoping `[gone]` to `%(upstream:short)` equal to `origin/<branch>` is what makes it evidence
about this branch.

An upstream on its own is **not** evidence either. `git checkout -b <branch> origin/<base>`
sets one without pushing anything, so testing `%(upstream)` for non-empty would sweep away a
branch started thirty seconds ago.

**Merged but never pushed is a skip, deliberately.** Ancestry proves the commits are in the
base; it does not prove the branch is residue. This sweep collects the residue of shipped
work, and a branch that was never pushed shipped nothing — no remote head, no pull request,
nothing saying the operator was finished with it. A local branch parked at or below the base
is an ancestor, so ancestry alone would collect every bookmark and just-created branch in the
checkout. Row 4 reports such a branch as a skip on every sweep and the operator deletes it by
hand: never-pushed local work is the one thing here that no remote copy can restore.

**Row 5 is about tracked files only, and removing a worktree destroys the ignored ones.**
`git status --porcelain` says nothing about `.env`, `node_modules`, or local build state, so a
worktree holding them reads clean and `git worktree remove` deletes them without `--force`.
Under the old predicate almost no worktree reached this; now every clean merged branch's does.
Name the path in the plan and say that ignored files there go with it —
`git status --porcelain --ignored <path>` lists what would be lost, when the operator asks.

**Row 7 costs one `gh` call per branch that reaches it**, and repo-wide enumeration sends more
branches there than `[gone]` alone did. The row order is the bound: rows 1–6 are local and
free apart from step 5's single call, so the per-branch call fires only for a branch that was
pushed and is *not* an ancestor of the base — the set that is either squash-merged or
genuinely unmerged, small in a working checkout but not bounded in principle. A checkout
carrying dozens of pushed, unmerged branches is that many serial API calls, and they are the
sweep's dominant latency and its whole rate-limit cost. Rate-limited or without `gh`, those
branches fall to row 8 and are reported rather than deleted, so exhaustion costs a missed
collection, never a wrong deletion.

The squash-merged row exists because a squash or rebase merge rewrites the commits: GitHub
says merged, git ancestry says not. Without it, this skill would report the same leftovers
forever in any repo that squashes. A merged PR for that exact head is the evidence — absent
it, the branch is unmerged and stays.

**Deletion rules:**

- **Row 6 and row 7 are the only land checks.** Do not read `git branch -d` as a second,
  independent guard: it tests a branch against its own upstream when it has one and against
  your current `HEAD` otherwise, never against `origin/<base>`. On the squash path it prints
  `merged to 'refs/remotes/origin/<branch>', but not yet merged to HEAD` and **succeeds** on a
  branch that is no ancestor of the base. A branch with its own upstream is precisely what
  push evidence selects for, so that is the whole population reaching these rows.
- Try `-d` first anyway, since its refusals are informative, and fall back to `-D` for a
  branch rows 6 or 7 already classified and for nothing else. Never `-D` a branch classified
  unmerged — that needs the operator naming it after seeing it in the plan.
- Remove a branch's worktree *before* deleting the branch: `git worktree remove <path>`, since
  `git branch -d` refuses a branch checked out in any worktree. Never `--force` — a dirty
  worktree is a skip, not something to bulldoze. Never remove the main checkout or the
  worktree the sweep is running in.

## Output contract

- one `deleted <branch> (<sha>)` line per deletion, plus `removed worktree <path>` when one
  was attached — report the sha1 git prints, since `git branch <name> <sha>` restores it, and
  the path, since nothing restores the ignored files that were under it
- one line per skip, with its reason
- `nothing to prune — no branch classified merged or squash-merged` when the delete set is
  empty, and stop there. It is a statement about the *delete* set, not the candidate set:
  repo-wide enumeration leaves the latter empty only in a repo with no local branches.
- close with counts: N deleted, M skipped, and the unmerged list if non-empty

## Hard constraints

- Confirm `origin` exists and `git fetch --prune` succeeds before any evaluation, and stop if
  the base branch does not resolve. Every row below reads `refs/remotes/origin`, and a stale,
  absent, or misidentified reference is worse than no sweep.
- Candidates are every local branch, read from `for-each-ref` plumbing, never from grepping
  `git branch` output. The ordered rows decide what happens to each, not the enumeration.
- Never delete the base branch, a protected branch, a branch checked out in the main worktree
  or in the sweep's own worktree or in two worktrees at once, or a branch with no evidence of
  ever having been pushed under its own name.
- One confirmation before the first deletion; list every branch, and every worktree path the
  plan would remove, before acting on it.
- Never `git worktree remove --force`; never `-D` an unmerged branch.
- Never run the sweep while a campaign or dispatched worker is in flight; it cannot tell a
  live worktree from an abandoned one.
