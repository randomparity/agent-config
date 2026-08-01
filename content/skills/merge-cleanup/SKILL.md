---
name: merge-cleanup
description: "Hand off a green, mergeable pull request or merge it when explicitly authorized, then clean merged branches and worktrees. Use after shipping a PR or when asked to merge and clean up completed work."
---
# Hand Off or Merge, Then Clean Up

When `$ship-pr`'s exit condition holds — required checks green and the PR is
mergeable — you are at the hand-off point.

## Default: hand off, do not self-merge

First record the hand-off (github-tracking skill): post a `WORK:TRAJECTORY` comment on the
issue with `outcome: handed off — PR #N green+mergeable, awaiting human merge`, guardrail
status, and any surprises. **Leave the issue open and `status:awaiting-merge` intact** — do
not close, do not strip. The eventual human UI-merge auto-closes it and `$recover-orphans`
strips the residual label (closed-state is authoritative).

Only then tell the user the PR is ready to merge and stop. The tracking write is the durable
hand-off record the resume story depends on — it must happen before this terminal stop.

## Exception: operator-authorized merge

If the operator explicitly authorized merging, you may merge it yourself. The
authorization holds in exactly two cases:

- a direct human instruction this session (including a goal you typed asking for
  these issues to be *merged* — distinct from a `$review-loop` stop goal, which
  never authorizes a merge), or
- you are the **`$campaign` orchestrator itself** and merging is its stated
  completion condition.

Authorization does **not** inherit through delegation. If you are a `$work-issue`
run that a `$campaign` dispatched — inline or as a subagent — you are **not**
authorized: stop at hand-off (green + mergeable) and let the orchestrator merge.
When you do merge:

- Use the repo's required merge method. Per common convention, **do not squash
  code PRs** — squashing collapses the small logically-scoped commits that
  `git bisect` relies on. Use `--rebase` (linear history) or `--merge` unless
  the repo says otherwise. Squash is acceptable only for pure doc/spec
  review-iteration PRs.
- When several sibling PRs are in flight, **merge serially**: merge one, then
  for each remaining PR re-check `mergeStateStatus`; if it went
  `BEHIND`/`DIRTY`, rebase it onto the updated `BASE_BRANCH`, regenerate
  generated artifacts, rerun guardrails, and confirm green + mergeable again
  before merging it. Never merge an unmergeable PR on the strength of
  previously-green checks.

**Caller contract.** If invoked inside `$work-issue`, completing the cleanup
means the issue is done — end your turn with a summary. If running standalone,
the same applies: once cleanup is verified, report and stop.

## Track state on the operator-merge path (github-tracking skill)

The default hand-off path already posted its `WORK:TRAJECTORY` above. This section covers the
operator-merge path only:

- **Operator-merge path** (you merged, above): if `Closes #N` did not auto-close the issue,
  close it; strip its `status:` labels; post a `WORK:TRAJECTORY` comment on the issue with
  `outcome: merged via PR #N`, guardrail status, and any surprises.

### Release cleared dependents

After verifying the merged issue is closed, run the `github-tracking` skill's canonical
recipe in Bash and call `reconcile_cleared_dependencies apply <owner/name>`. This is the primary
owner of the cleared-dependency `status:blocked → status:ready` edge. Report every readied
dependent and every retained dependent with its actionable reason. Do not limit the scan to
the merged issue's prose or comments: the recipe exhaustively evaluates canonical whole-line
`Blocked by #N` records on all open blocked, non-epic issues. A per-dependent failure does
not prevent other dependents from being evaluated.

## After a merge (yours or the user's)

1. Switch to `BASE_BRANCH`.
2. Fast-forward pull.
3. Delete the merged local branch.
4. Prune remote-tracking branches.
5. Remove any external worktree you created for this issue
   (`git worktree remove`).
6. Verify the working tree is clean.
