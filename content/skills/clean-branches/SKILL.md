---
name: clean-branches
description: "Sweep local branches that are merged, squash-merged, or have a gone upstream, remove their worktrees after confirmation, delete them, and report every deletion. Use when asked to clean merged or gone branches or prune stale local branch state."
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

1. **Refresh tracking state.** `git fetch --prune`. Both the ancestry test and the
   `never pushed` row are claims about remote-tracking refs, and a stale one is worthless. If
   the fetch fails (no remote, offline, auth), stop and say so — do not evaluate a single
   branch against stale state.
2. **Resolve the base branch.** `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`;
   without `gh`, `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/`.
   Every ancestry test below runs against `origin/<base>` — the ref you just fetched, not a
   local base that may be behind.
3. **Enumerate candidates** — every local branch — with plumbing, not porcelain:

   ```bash
   git for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads
   ```

   Repo-wide on purpose. Filtering here on `%(upstream:track)` equal to `[gone]` found only
   branches whose own remote head had been deleted, which made the `merged` and
   `squash-merged` rows below unreachable for the leftovers this sweep exists to collect: a
   branch created by `git worktree add <path> -b <branch> origin/<base>` tracks the *base*, so
   its track field reads `[ahead N, behind M]`, and pushing it with `-u` only moves that to
   `[behind N]` or empty. A repo with `deleteBranchOnMerge: false` then keeps the remote head
   after the merge, so a pruned fetch cannot produce `[gone]` either. The track field is still
   read — the `never pushed` row uses it — but it no longer decides who gets looked at.

   Enumerating more does not delete more. Every branch runs the full classification below, and
   only `merged` and `squash-merged` delete.
4. **Read the remote heads, once**, for the `never pushed` row:

   ```bash
   git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin
   ```

   One command for the whole sweep; intersect names locally rather than probing per branch.
5. **Map worktrees.** `git worktree list --porcelain` — records separated by blank lines,
   each with a `worktree <path>` and, when a branch is checked out, `branch refs/heads/<name>`.
   The first record is the main checkout. Build branch → path.
6. **Classify every candidate** (table below) before touching anything.
7. **Plan → confirm.** Present one table — `branch → classification → action` — including the
   skips and their reasons, and naming the path of every worktree the plan would remove. Take
   one explicit confirmation, then apply. A failure on one branch does not abort the sweep.

## Classification

Test each branch against these rows **in order; first match wins.** The order is load-bearing
now that enumeration is repo-wide: the base branch is an ancestor of `origin/<base>`, so an
unordered table would classify it `merged` and delete it.

| # | Candidate | Test | Action |
|---|---|---|---|
| 1 | base branch | name equals `<base>` | skip, name it |
| 2 | checked out in a protected worktree | branch is the main checkout's HEAD, or the HEAD of the worktree the sweep is running in | skip, name it |
| 3 | never pushed | no `refs/remotes/origin/<branch>` from step 4, **and** `%(upstream:track)` is not `[gone]` | **skip, never delete** |
| 4 | dirty worktree | `git status --porcelain` in its worktree is non-empty | skip, name it |
| 5 | merged | `git merge-base --is-ancestor <branch> origin/<base>` succeeds | delete |
| 6 | squash-merged | not an ancestor, but `gh pr list --head <branch> --state merged --json number,title --limit 1` returns a PR | delete; the plan line names the PR |
| 7 | unmerged | neither — no ancestry, no merged PR (or no `gh`/GitHub remote) | **report, never delete** |

Row 2 covers the sweep's own worktree because `git worktree remove` will happily remove the
directory you are standing in and leave you with no working directory.

**This sweep has no liveness signal, and enumeration is now repo-wide, so any *other* linked
worktree it reaches may belong to an agent that is still running.** A dispatched worker's
pull request merges some way before the worker itself stops, and in that window the branch is
an ancestor of the base and the worktree is live. Do not run the sweep while a campaign or a
dispatched worker is in flight. Row 4 catches only the workers that left files behind.

**Never delete a never-pushed branch.** Row 3 states a rule that used to be an accident of
enumeration — a branch with no upstream yielded an empty track field and was never a
candidate. State it positively: a branch is deletable only on *evidence that it was pushed*,
never on the absence of evidence that it was not. That evidence is a remote head under the
branch's own name, or a `[gone]` track field asserting such a head existed and was deleted;
the two cover both settings of `deleteBranchOnMerge`. An upstream is **not** evidence —
`git checkout -b <branch> origin/<base>` sets one without pushing anything, so testing
`%(upstream)` for non-empty would sweep away a branch started thirty seconds ago.

**Merged but never pushed is a skip, deliberately.** Ancestry proves the commits are in the
base; it does not prove the branch is residue. This sweep collects the residue of shipped
work, and a branch that was never pushed shipped nothing — no remote head, no pull request,
nothing saying the operator was finished with it. A local branch parked at or below the base
is an ancestor, so ancestry alone would collect every bookmark and just-created branch in the
checkout. Row 3 reports such a branch as a skip on every sweep and the operator deletes it by
hand: never-pushed local work is the one thing here that no remote copy can restore.

**Row 6 costs one `gh` call per branch that reaches it**, and repo-wide enumeration sends more
branches there than `[gone]` alone did. The row order is the bound: rows 1–5 are local and
free, so the call fires only for a branch that was pushed and is *not* an ancestor of the base
— the set that is either squash-merged or genuinely unmerged, small in a working checkout but
not bounded in principle. A checkout carrying dozens of pushed, unmerged branches is that many
serial API calls, and they are the sweep's dominant latency and its whole rate-limit cost.
Rate-limited or without `gh`, those branches fall to row 7 and are reported rather than
deleted, so exhaustion costs a missed collection, never a wrong deletion.

The squash-merged row exists because a squash or rebase merge rewrites the commits: GitHub
says merged, git ancestry says not. Without it, this skill would report the same leftovers
forever in any repo that squashes. A merged PR for that exact head is the evidence — absent
it, the branch is unmerged and stays.

**Deletion rules:**

- Try `git branch -d` first, so git's own merged-check is a second, independent guard.
- Fall back to `-D` in exactly two cases: a branch whose ancestry against `origin/<base>`
  already proved merged but whose `-d` was refused because HEAD is not the base branch
  (git's check is against HEAD, not the base you tested), and a squash-merged branch, where
  `-d` can never succeed by construction. Never `-D` a branch classified unmerged — that
  needs the operator naming it after seeing it in the plan.
- Remove a branch's worktree *before* deleting the branch: `git worktree remove <path>`.
  Never `--force` — a dirty worktree is a skip, not something to bulldoze. Never remove the
  main checkout or the worktree the sweep is running in.

## Output contract

- one `deleted <branch> (<sha>)` line per deletion, plus `removed worktree <path>` when one
  was attached — report the sha1 git prints, since `git branch <name> <sha>` restores it
- one line per skip, with its reason
- `nothing to prune — no branch classified merged or squash-merged` when the delete set is
  empty, and stop there. It is a statement about the *delete* set, not the candidate set:
  repo-wide enumeration leaves the latter empty only in a repo with no local branches.
- close with counts: N deleted, M skipped, and the unmerged list if non-empty

## Hard constraints

- `git fetch --prune` before any evaluation; both `[gone]` and the `never pushed` row read
  tracking refs, and a stale one is worthless.
- Candidates are every local branch, read from `for-each-ref` plumbing, never from grepping
  `git branch` output. The ordered rows decide what happens to each, not the enumeration.
- Never delete the base branch, a branch checked out in the main worktree or in the sweep's
  own worktree, or a branch with no evidence of ever having been pushed.
- One confirmation before the first deletion; list every branch, and every worktree path the
  plan would remove, before acting on it.
- Never `git worktree remove --force`; never `-D` an unmerged branch.
- Never run the sweep while a campaign or dispatched worker is in flight; it cannot tell a
  live worktree from an abandoned one.
