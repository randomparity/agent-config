---
description: Sweep local branches whose upstream is gone — remove their worktrees, delete them, report every deletion
argument-hint: '(no args — sweeps the current repo)'
allowed-tools: Read, Bash(git fetch:*), Bash(git for-each-ref:*), Bash(git worktree:*), Bash(git branch:*), Bash(git merge-base:*), Bash(git rev-parse:*), Bash(git symbolic-ref:*), Bash(git status:*), Bash(gh repo view:*), Bash(gh pr list:*)
---

# Clean Gone Branches

Repo-wide hygiene sweep for local branches whose upstream is gone. `/merge-cleanup` deletes
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

1. **Refresh tracking state.** `git fetch --prune`. `[gone]` is a claim about remote-tracking
   refs, and a stale one is worthless. If the fetch fails (no remote, offline, auth), stop
   and say so — do not evaluate a single branch against stale state.
2. **Resolve the base branch.** `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`;
   without `gh`, `git symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/`.
   Every ancestry test below runs against `origin/<base>` — the ref you just fetched, not a
   local base that may be behind.
3. **Enumerate candidates** with plumbing, not porcelain:

   ```bash
   git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads \
     | awk '$2=="[gone]" {print $1}'
   ```

   `%(upstream:track)` emits `[gone]` as a discrete field, so this is an exact match. A
   branch with no upstream yields an empty field and is not a candidate — never delete a
   never-pushed branch. If the set is empty, report that and stop; there is nothing to plan.
4. **Map worktrees.** `git worktree list --porcelain` — records separated by blank lines,
   each with a `worktree <path>` and, when a branch is checked out, `branch refs/heads/<name>`.
   The first record is the main checkout. Build branch → path for the candidates only.
5. **Classify every candidate** (table below) before touching anything.
6. **Plan → confirm.** Present one table — `branch → classification → action` — including the
   skips and their reasons. Take one explicit confirmation, then apply. A failure on one
   branch does not abort the sweep.

## Classification

| Candidate | Test | Action |
|---|---|---|
| merged | `git merge-base --is-ancestor <branch> origin/<base>` succeeds | delete |
| squash-merged | not an ancestor, but `gh pr list --head <branch> --state merged --json number,title --limit 1` returns a PR | delete; the plan line names the PR |
| unmerged | neither — no ancestry, no merged PR (or no `gh`/GitHub remote) | **report, never delete** |
| checked out in the main worktree | branch is the main checkout's HEAD | skip, name it |
| dirty worktree | `git status --porcelain` in its worktree is non-empty | skip, name it |

The squash-merged row exists because a squash or rebase merge rewrites the commits: GitHub
says merged, git ancestry says not. Without it, this command would report the same leftovers
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
  main checkout.

## Output contract

- one `deleted <branch> (<sha>)` line per deletion, plus `removed worktree <path>` when one
  was attached — report the sha1 git prints, since `git branch <name> <sha>` restores it
- one line per skip, with its reason
- `no branches matched — nothing to prune` when the candidate set is empty, and stop there
- close with counts: N deleted, M skipped, and the unmerged list if non-empty

## Hard constraints

- `git fetch --prune` before any evaluation; never judge `[gone]` on stale tracking refs.
- Candidates come from `%(upstream:track)`, never from grepping `git branch` output.
- Never delete the base branch or a branch checked out in the main worktree.
- One confirmation before the first deletion; list every branch before acting on it.
- Never `git worktree remove --force`; never `-D` an unmerged branch.
