# 0044 — Cleanup waits on the same observed end of run

## Status

Accepted (2026-08-10)

## Context

Record 0042 gave `campaign` step 5 a rule about when a dispatched agent may be treated as
finished: **only an observed end of run authorizes re-dispatch.** It scoped that rule to
re-dispatch, because re-dispatch was the destructive action the filed issue was about. Step
6 was left alone, and step 6 also destroys things.

Step 6 merges a pull request, verifies the auto-close, and ends with "Clean up branch and
worktree." Nothing between the merge and that sentence asks whether the agent that owns the
worktree has stopped, and the paragraph above it states outright that "In parallel mode,
subagent is done and worktree may be gone." That is a premise, not a check, and it is false
often enough to matter.

It is false because of where a dispatched `$work-issue` run actually stops. Its step 9 runs
`$merge-cleanup`, which for a campaign-dispatched worker takes the **hand-off** path: post
`WORK:TRAJECTORY`, leave the issue open at `status:awaiting-merge`, report, stop. That path
never reaches `$merge-cleanup`'s "After a merge" list, so the worker never removes its own
worktree — and it is still running for some stretch after its pull request first reads green
and mergeable, which is exactly when the orchestrator starts merging. The orchestrator is
therefore cleaning up a directory whose owner is, by construction, sometimes still inside it.

That race was observed during the campaign that closed #87 #88 #89 #90 #91. Merging #109
produced:

```
push-check exit 127
fatal: Unable to read current working directory
```

The worker had noticed `BASE_BRANCH` move and was merging it back into its branch so the
orchestrator would not receive a stale result. The worktree was removed while that push was
in flight, so the pre-push hook ran with no working directory to run in.

Two things make this worth a rule rather than a caution. The error text reads like
filesystem corruption, so an agent that hits it starts diagnosing the wrong problem. And the
behaviour it punishes is the behaviour the orchestrator asked for: refreshing against a moved
base is the disciplined thing, and the race fires specifically on the agent doing it.

Nothing was lost that time. The orchestrator had confirmed `git diff --stat` between the base
and the branch was empty before deleting, so the only unpushed commit was a content-free
merge commit. That was the blast radius being small, not the race being absent.

The same premise has a second consequence in the same step. When a sibling pull request goes
`BEHIND` and the orchestrator refreshes it, the branch is still checked out in the live
worker's worktree, so the orchestrator's own `git worktree add` on that branch fails. Step 6
tells it to "check out branch in fresh external worktree" as though that always works.

Record 0042 is Accepted and merged, and merged records are immutable — the constraint is in
`content/skills/decision-records/SKILL.md`. Extending its rule to a second action is a new
decision, and its philosophy is a constraint on that decision: liveness is **observed**, not
instrumented.

## Decision

**Removing a worker's worktree and deleting its branch require the same observed end of run
that record 0042 requires for re-dispatch. Merging does not.**

**The merge and the cleanup separate.** Merging is a server-side operation on refs that are
already pushed; no live agent's working tree is reachable from it. Removing a directory an
agent is `cd`-ed into is reachable from it, and that is the whole of the observed failure. So
the precondition guards cleanup alone, and a live agent never delays a merge, a row's
`merged` status, or the queue behind it.

**The signal is the one 0042 already named**, unchanged: the harness's own end-of-run
notification for the agent dispatched on that row, or the orchestrator stopping that agent
through the harness's stop control and then seeing the notification. Nothing weaker
substitutes. A merged pull request, a green check, a `WORK:REVIEW`, and an answered probe
each prove the agent *reached* something; none proves it stopped. The probe keeps the
asymmetry it has in 0042 and gains no new power here: a reply proves the agent alive, so it
can only ever tell the orchestrator to wait, never to proceed.

**A merged row is drained whether or not it has been cleaned.** Step 8's `drained` stays
`closed | merged | blocked`, and a row reaches `merged` at the merge. Cleanup is filesystem
hygiene, not a campaign outcome; the issue is closed and the work has landed. Gating
`drained` on cleanup would hold an entire campaign open behind one agent, and 0042's own
consequences say a hung agent that still answers messages reads as alive indefinitely — so
that wait has no bound. It would also reproduce, at the end of the run, precisely the stall
0042 was filed against.

**Deferred cleanup belongs to the orchestrator, and it is carried in the run rather than
written down.** This is 0042's stance on holds, applied to the same subject: no new file, no
new manifest column, no `status:` label. The orchestrator keeps the deferred rows in its run
output, retries a row when that agent's end-of-run notification arrives, sweeps once more
before the final report, and names by path whatever is still uncleaned. The list is
recoverable rather than remembered — `git worktree list` against the merged rows' branches
recomputes the paths and the branches in seconds — which is the same property that let 0042
store nothing. Which *agent* owned a row is the one part that does not recompute; losing it
to a restart costs the report a name and not the cleanup, so it is not worth a file to keep.

The orchestrator owns it because the orchestrator is the only party that can. It is the one
that receives the end-of-run notification, the one holding the queue the retry rides on, and
the one that outlives the worker. `$merge-cleanup` has none of those: no queue, no poll, and
no notification about an agent it did not dispatch.

**`$merge-cleanup` removes only the worktree its own run created, and now says so.** That
step was already scoped to "any external worktree you created", and the orchestrator did not
create the worker's. But it sits in a flat numbered list that reads as unconditional, and
campaign step 6's "Clean up branch and worktree" invited the removal regardless — so between
the two skills the exclusion existed in one place and was overridden in the other.
`$merge-cleanup` states the exclusion explicitly and hands an unowned worktree back to its
caller as a reported deferral.

Its **branch** deletion needs no matching scope, and does not get one. Git already refuses to
delete a branch checked out in another worktree, by `-d` or `-D` alike, so the guard is in the
tool rather than in the prose; and `$clean-branches` documents `$merge-cleanup` as the thing
that "deletes the one branch it just merged, in flow", which a scope here would quietly
falsify.

What `campaign` replaces in that list is **only** its worktree removal and its branch
deletion. The rest of `$merge-cleanup` still runs on the orchestrator's path, and two parts of
it are relied on rather than merely tolerated: the tracking writes and the cleared-dependency
reconcile, which step 6 does not repeat and which own the `status:blocked → status:ready` edge
between interdependent rows; and the switch to `BASE_BRANCH` with its fast-forward pull, which
advances the local base the `BEHIND` refresh merges and moves the orchestrator off a branch it
is about to delete. Superseding the whole list would have silently dropped all of that.

Two orderings in that list were wrong once the scoping was made explicit, and are corrected
with it. Worktree removal now precedes branch deletion, because the run's own branch is
checked out in the run's own worktree and the old order refused every time it mattered. And
the list now begins by returning to the main checkout: a `$work-issue` run executes it from
inside the worktree it created, where switching to the base branch fails and removing "the
worktree this run created" removes the directory the agent is standing in — reproducing this
record's own failure, self-inflicted.

**The precondition binds to an agent this run dispatched.** Two ordinary rows have no such
agent and never will: one adopted on resume with its pull request already open, and one whose
cleanup an earlier run deferred. A notification that cannot arrive is not a precondition, it
is a permanent leak, so those rows are decided on what is observable instead — `git worktree
list` showing the branch checked out nowhere, and `git status --porcelain` empty inside a
worktree that does hold it. Both are readable before anything is removed, which the obvious
alternative — "a worktree `git worktree remove` accepts is one that was not in use" — is not:
it can only be evaluated by performing the very step it is supposed to authorize.

**The did-it-land check stays required, and stays independent of the liveness check.** It
answers a different question — whether the branch still carries work the base does not — and
an observed end of run does not answer it: an agent can end having left a commit that never
landed. It was also what kept the observed incident harmless, so it earns its place.

It is an **ancestry** test, not a diff: `git merge-base --is-ancestor <branch>
origin/<BASE_BRANCH>`, which is the test `$clean-branches` already uses, and the reason
matters here more than there. `git diff <BASE_BRANCH> <branch>` is a symmetric
tree comparison, so once any *sibling* merges into the base it reports that sibling's changes
as deletions on a branch that landed perfectly — and deferred rows are by construction the
ones swept after later merges, so the deferral this record creates would clean nothing. The
orchestrator that ran `git diff --stat` in the observed incident got a true answer only
because it was the first merge of the wave.

**The squash fallback is a SHA identity, not a branch-name lookup.** A squash or rebase merge
rewrites the commits, so ancestry is false for a branch that landed and the test needs a
second route. `$clean-branches` takes it by asking whether a merged pull request exists for
that head branch, which is sound in a repo-wide sweep and unsound here: the orchestrator has
just merged that pull request for that branch, so the lookup hits unconditionally and the
required check reduces to a no-op — on exactly the case it was written for, since a branch
that gained a commit *after* the merge still matches by name. The fallback is therefore
`gh pr view <PR> --json headRefOid` equal to `git rev-parse <branch>`. A branch that moved
after its merge fails both tests and is deferred, which is what the observed incident would
have produced.

The order is: satisfy the liveness precondition, confirm the branch landed, remove the
worktree, then delete the branch. Worktree before branch matches `$clean-branches`, and for
the same reason: a branch checked out in a worktree cannot be deleted. `git branch -d` is not
a second land check and is not treated as one: it tests against the branch's own upstream when
it has one and against `HEAD` otherwise, never against `origin/<BASE_BRANCH>`, so on the
squash path it warns and then *succeeds* on a branch that is no ancestor of the base. `-D` is
permitted for the two cases the land check proved merged and for nothing else.

**A worktree that refuses to be removed is a deferral, not a case for `--force`.**
`git worktree remove` refuses on modified or untracked files, and a finished worker's worktree
routinely holds some. Forcing past it discards exactly the uncommitted work the whole record
exists to protect, so the refusal joins the same deferred list.

**The corrected premise applies to the branch refresh too.** When a `BEHIND` sibling needs
`BASE_BRANCH` merged in and its worker is still alive, the orchestrator cannot take the
branch into a worktree of its own. The row waits for that agent's end of run — or for
`git worktree list` to show the branch checked out nowhere, which is the same fact reached
without a notification — or the agent is asked to do the refresh, which is the thing it was
already doing when this race was found.

The end of run alone does not release the branch, and the skill must not imply it does. The
worker never removes its own worktree, so the branch stays checked out there after it stops
and `git worktree add` still fails. The orchestrator reclaims the worktree first — taking
over the path or removing it — which is the same reclaim step 5 already performs before a
re-dispatch, for the same reason.

## Consequences

- Nothing is instrumented. The precondition reuses 0042's two signals exactly as they are, so
  no contract spans `campaign` and `$work-issue` and no future edit to either can break the
  other's story.
- Steps 5 and 6 now assert the same fact about a dispatched agent, so the disagreement the
  issue names is gone and a future edit to one is visibly an edit to the other's premise.
- A campaign can end with worktrees still on disk and merged branches still present. That is
  the cost, and it is paid deliberately: a leaked directory is recoverable and named in the
  report, while a directory removed from under a running process is not.
- The fallback owner is usually the operator alone. `$clean-branches` looks like the standing
  sweep for this and mostly is not: it enumerates candidates by `%(upstream:track)` equal to
  `[gone]`, and merging a pull request leaves `origin/<branch>` in place, so the track field
  reads empty rather than `[gone]` and the sweep passes the branch over. The exception is a
  repository that deletes head branches on merge, where a pruned fetch does make it `[gone]`
  and the sweep does collect it. Relying on that would make recovery a function of one
  repository setting, so the report naming the paths is what this record depends on. Closing
  the gap properly is a change to `$clean-branches`, tracked separately rather than folded in
  here.
- Cleanup now depends on a harness notification, and the degradation without one is worse than
  0042's. There, a missing notification cost only automatic re-dispatch. Here it also costs the
  `BEHIND` refresh, and a sibling that can never be refreshed is a row that can never merge. So
  the notification is not the sole route. For a row this run did **not** dispatch,
  `git worktree list` settles it without one. For a row it did, that query cannot help — the
  worker's own worktree still holds the branch, which is the premise two paragraphs above — and
  the surviving route is to ask the live agent to perform its own refresh. Cleanup on such a
  harness falls to the operator; the queue does not stick.
- The branch refresh for a `BEHIND` sibling can now wait on a live worker instead of
  proceeding. Merges of *other* rows are unaffected, since each row's refresh is independent.
- A worker that hangs after its pull request merges holds one worktree, not the campaign.
  Accepted: that is the whole point of keeping `drained` where it is.
- A worktree holding untracked or modified files is skipped rather than removed, so a worker
  that leaves scratch files behind leaks its worktree even having ended cleanly. That is the
  right trade — the alternative is `--force`, which deletes the stranded work — but it means
  the deferred list is not only about live agents. It holds three reasons now — end of run not
  observed, worktree not clean, branch did not land — and only the first can resolve itself,
  so the report states which applied per row rather than listing paths.
- Deferral is deliberately not step 6's existing hold. That hold takes the blocker path: a
  `WORK:TRAJECTORY` note, a `status:` label, a `blocked` manifest row. Reusing it here would
  put a status label on an issue the merge just closed and keep the manifest `active` over a
  directory on disk. The word is avoided in the skill for that reason.
- Deciding a resume-adopted row on `git worktree list` rather than a notification is weaker
  than the rule it stands in for: a worktree from a *different* live session would read as
  unheld if that session had committed everything and touched nothing since. The exposure is
  bounded to a merged branch whose content is already in the base, and the alternative —
  never cleaning a row this run did not dispatch — leaks every one of them forever.

## Considered & rejected

- **A lockfile, heartbeat, PID registry, or any other liveness instrumentation.** Rejected:
  0042 rejected instrumentation for the *harder* question — telling a silent agent from a
  dead one — and cleanup asks the easier one, for which the harness already supplies a
  definitive answer at no cost. Adding a mechanism here would buy a weaker signal than the
  one already in hand, and contradict an accepted record to do it.
- **Holding the row non-drained until its worktree is cleaned.** Rejected: an unbounded wait
  on a party 0042 says may never stop, in exchange for a filesystem tidy. It converts a leaked
  directory into a campaign that cannot end.
- **`git worktree remove --force`.** Rejected: `$clean-branches` already forbids it, and
  forcing is the failure mode rather than a way around it — it discards the stranded
  uncommitted edits and yanks the working directory, which is what the observed error was.
- **Giving `$merge-cleanup` the deferral.** Rejected: it would have to hold a retry list
  across a run it does not own, keyed on notifications it never receives. It gets the
  exclusion, which is decidable from what its own run did; the orchestrator gets the deferral,
  which is not.
- **Deferring the merge as well, until the agent ends.** Rejected: merging touches nothing the
  agent holds, and delaying it serialises the campaign behind its slowest worker for no safety
  gain — while the pull requests behind it go `BEHIND` and need the refresh this record just
  made conditional.
- **Persisting the deferred-cleanup list in the campaign manifest.** Rejected on 0042's
  grounds, which apply unchanged: the manifest is single-writer, slug-keyed to one selector on
  one machine, and gitignored, so it is the wrong channel for state about a party that is not
  its writer. A stored copy could only go stale against `git worktree list`, which answers the
  same question live.
- **Treating the merged pull request as the end-of-run signal.** Rejected: it is the signal
  that was already there, and the race is the proof it is the wrong one. The pull request
  going green is the moment the worker starts its hand-off, not the moment it finishes.
