# 0048 — Sweep branches on push evidence, not on a gone upstream

## Status

Accepted (2026-08-10)

## Context

Record 0044 accepted that a campaign can end with merged branches and their worktrees still
on disk, and named the operator as the usual fallback owner because `$clean-branches` cannot
collect them. Its reasoning: the sweep enumerates candidates by `%(upstream:track)` equal to
`[gone]`, and merging a pull request in a repository with `deleteBranchOnMerge: false` leaves
`origin/<branch>` in place, so the track field never reads `[gone]`. It closed by saying that
closing the gap properly is a change to `$clean-branches`, tracked separately. This is that
change.

The situation is worse than "mostly does not work". `[gone]` is unreachable for a worker's
branch for two independent reasons, both observed on this repository:

- A branch created by `git worktree add <path> -b <branch> origin/<base>` has its upstream set
  to the **base**, not to a head of its own, so its track field reads empty until its first
  commit and `[ahead N, behind M]` after. Pushing it with `-u` moves the upstream to
  `origin/<branch>`, whose track then reads empty or `[behind N]`. No state in that sequence
  is ever `[gone]`. A branch created without an upstream at all reads empty throughout.
- After the pull request merges, `deleteBranchOnMerge: false` keeps the remote head, so a
  pruned fetch has nothing to prune and cannot produce `[gone]` either.

The consequence is that the `merged` and `squash-merged` rows of the skill's classification
table were unreachable for any branch that was not already `[gone]`. Record 0044 endorses
those two tests, so the defect is entirely in who reaches them.

Widening enumeration to every local branch is the obvious fix and is unsafe on its own,
because ancestry against `origin/<base>` is true of far more than the leftovers. A branch
created and not yet committed to, a bookmark parked at the base, and a merged worker branch
are all ancestors of it. The `[gone]` predicate was, by accident, also the rule that spared
the first two: a never-pushed branch has an empty track field, so it was never a candidate.
Deleting the predicate deletes that protection, and the protection has to come back on
purpose rather than as a side effect of the next predicate.

## Decision

**Enumerate every local branch, and delete on evidence that a branch was pushed — never on
the absence of evidence that it was not.**

Push evidence is either of two facts, both local and free once step 1's pruned fetch has run:

- a remote-tracking ref under the branch's own name, `refs/remotes/origin/<branch>`; or
- a `[gone]` track field **whose upstream was `origin/<branch>`**, which asserts that a head
  of the branch's own name existed and has been deleted.

The two together cover both settings of `deleteBranchOnMerge`: `false` keeps the head and the
first fact holds, `true` prunes it and the second does. A branch with neither is classified
`never pushed` and skipped whatever its ancestry, which makes the rule the skill previously
only implied into a row of its own.

**The name scoping on the `[gone]` clause is not decoration.** `[gone]` is a fact about
whatever the branch tracks, not about the branch: `git switch -c mine origin/theirs` pushes
nothing, and when the colleague's pull request merges and their head is deleted, `mine` reads
`[gone]` while `refs/remotes/origin/mine` never existed — and `mine` is by then an ancestor of
the base. An unscoped clause would delete a never-pushed branch, which is the exact failure
this decision exists to prevent.

**An upstream is not push evidence.** `git checkout -b <branch> origin/<base>` sets one
without pushing anything, so a non-empty `%(upstream)` is equally true of a campaign worker's
branch and of a local branch started thirty seconds ago.

**A merged branch with no push evidence is skipped, and stays skipped.** Ancestry proves the
commits are in the base; it does not prove the branch is residue. This sweep collects the
residue of shipped work, and a branch that was never pushed shipped nothing — there is no
remote head and no pull request anywhere saying the operator was finished with it. Such a
branch is reported as a skip on every sweep and deleted by hand.

**The classification rows are ordered and the first match wins.** Repo-wide enumeration makes
several rows true of one branch at once, and the base branch is itself an ancestor of
`origin/<base>`; an unordered table would classify it `merged`.

**Widening enumeration admits a category the `[gone]` predicate never reached, so the table
gains a protected-branch row.** A long-lived integration branch — `release/1.2` merged into
the base with `--no-ff` and kept — is an ancestor with a live remote head, and no local test
distinguishes it from a feature branch nobody cleaned up. The remote's branch-protection
setting is the signal that does, so the sweep reads it once per run.

## Consequences

- The leftovers 0044 deliberately creates are collectable by the sweep, in either repository
  setting, instead of by the operator alone. Collectable, not standing: the sweep has no
  liveness signal of its own, so it must not run while a dispatched worker is in flight, and
  0044 defers cleanup precisely when a worker's end was *not* observed. The operator still
  chooses the moment; what changes is that the sweep then does the work instead of being a
  no-op. 0044's own prose about `$clean-branches` and the matching paragraph in `$campaign`
  step 6 describe the old behaviour and are now wrong; 0044 is an accepted record and is not
  rewritten, and the `$campaign` correction is issue #130 rather than a fold-in to a change
  whose scope the filed issue restricted to one file.
- A never-pushed branch that is an ancestor of the base is never collected automatically.
  That is a permanent, accepted gap and the direct cost of the decision above: at least one
  such branch exists on the machine that produced issue #116, and the sweep will report it
  as a skip forever. The alternative costs a local-only branch with no remote copy, which is
  the one thing in this sweep that a deletion cannot be undone from.
- Sweep output grows. Every local branch now appears in the plan table with a classification,
  where previously only `[gone]` branches did. That is the honest report of what the sweep
  considered, and the ordered rows make each spared branch say why it was spared.
- The pull-request lookup fires more often: once per pushed non-ancestor branch rather than
  once per `[gone]` non-ancestor branch. Ordering the free local rows ahead of it bounds the
  set to branches that are either squash-merged or genuinely unmerged, which is small in a
  working checkout but not bounded in principle. A rate-limited or absent `gh` degrades those
  branches to `unmerged`, which is report-only, so exhaustion costs a missed collection and
  never a wrong deletion.
- No new *kind* of branch can be deleted — only `merged` and `squash-merged` delete,
  `unmerged` is still report-only, and the operator naming a branch after seeing it in the
  plan is still the only route to deleting an unmerged one. But more branches reach those two
  rows, and that is a real exposure rather than a formality: a protected or long-lived
  integration branch that is an ancestor of the base was previously out of reach and is now
  spared only by the new row 2, whose input is a remote setting the sweep may be unable to
  read. Where `gh` cannot supply the protected set, the confirmation is the last guard, so
  the plan says the set was unknown instead of implying it was empty.
- Removing a worktree destroys the ignored files under it — `.env`, local build state — and
  `git status --porcelain` cannot see them, so the dirty-worktree row does not spare them.
  Testing `--ignored` there instead was rejected: it would skip every worktree with a
  `node_modules`, which is most of them, and turn the sweep back into the no-op this skill
  was written against. The plan names the path instead, and the deletion report keeps it.

## Considered & rejected

- **Keeping the `[gone]` predicate and adding a second enumeration pass for merged branches.**
  Rejected: two predicates feeding one classification table is two places to get the safety
  rules right, and the `[gone]` pass becomes a subset of the second one the moment push
  evidence is defined — `[gone]` *is* push evidence.
- **Treating a non-empty `%(upstream)` as push evidence.** Rejected: it is the reading that
  looks correct and is not. It happens to admit a campaign worker's branch and happens to
  exclude a branch created with `--no-track`, so it passes both cases in issue #116 while
  admitting every branch made with `git checkout -b <branch> origin/<base>` — the ordinary way
  to start work, and an ancestor of the base until its first commit.
- **Deleting a merged never-pushed branch anyway, since its commits are in the base.** Rejected
  on the asymmetry: a branch with a remote head can be restored from the remote, and one
  without can be restored only from a reflog that expires. The sweep reports the sha it
  deleted, which helps a human who notices; nothing helps one who does not.
- **Prompting per never-pushed merged branch instead of skipping.** Rejected: the skill takes
  exactly one confirmation before the first deletion, on purpose, and a per-branch prompt for
  the category most likely to be a deliberate bookmark trains the operator to answer without
  reading. Reporting it as a skip states the same fact and costs no decision.
- **Batching the pull-request lookup into one `gh pr list --state merged --json headRefName`
  query.** Rejected here as out of scope: it is a change to the `squash-merged` test, which
  0044 endorses as sound, and the per-branch call is only a latency and rate-limit cost whose
  failure mode is already safe. Worth revisiting if a checkout is ever slow enough to notice.
- **Using the reflog to decide whether a branch was ever pushed.** Rejected: `refs/remotes`
  answers the question directly and is refreshed by the fetch the sweep already runs, while a
  reflog is expiring, local, and absent in a fresh clone.
- **Dropping the `[gone]` clause entirely and testing only for `refs/remotes/origin/<branch>`.**
  Simpler, and rejected: in a repository with `deleteBranchOnMerge: true` the merge prunes
  that ref, so every branch the sweep was originally written to collect would classify
  `never pushed` and be skipped — before ever reaching the row where its merged pull request
  could vouch for it, since the never-pushed row has to come first to do its job. The name
  scoping above is what the clause actually needed.
- **Treating `git branch -d` as a second land check and keeping the sweep's old claim that it
  is one.** Rejected on measurement: `-d` tests against the branch's own upstream when it has
  one, so on the squash path it warns and succeeds on a branch that is no ancestor of the
  base. `$campaign` already documents this correctly; the two prompts disagreed, and the
  ancestry and pull-request rows are the only land checks.
