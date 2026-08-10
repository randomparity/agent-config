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

**The precondition binds to an agent this run dispatched.** Two ordinary rows have no such
agent and never will: one adopted on resume with its pull request already open, and one whose
cleanup an earlier run deferred. A notification that cannot arrive is not a precondition, it
is a permanent leak, so those rows are decided on what is observable instead — no worktree on
the branch means no holder, and a worktree `git worktree remove` accepts without `--force` was
not in use.

**The did-it-land check stays required, and stays independent of the liveness check.** It
answers a different question — whether the branch still carries work the base does not — and
an observed end of run does not answer it: an agent can end having left a commit that never
landed. It was also what kept the observed incident harmless, so it earns its place.

It is an **ancestry** test, not a diff: `git merge-base --is-ancestor <branch>
origin/<BASE_BRANCH>`, with a merged pull request for that exact head as the fallback where a
squash or rebase merge rewrote the commits. That is the test `$clean-branches` already uses,
and the reason matters here more than there. `git diff <BASE_BRANCH> <branch>` is a symmetric
tree comparison, so once any *sibling* merges into the base it reports that sibling's changes
as deletions on a branch that landed perfectly — and deferred rows are by construction the
ones swept after later merges, so the deferral this record creates would clean nothing. The
orchestrator that ran `git diff --stat` in the observed incident got a true answer only
because it was the first merge of the wave.

The order is: satisfy the liveness precondition, confirm the branch landed, remove the
worktree, then delete the branch. Worktree before branch matches `$clean-branches`, and for
the same reason: a branch checked out in a worktree cannot be deleted.

**A worktree that refuses to be removed is a deferral, not a case for `--force`.**
`git worktree remove` refuses on modified or untracked files, and a finished worker's worktree
routinely holds some. Forcing past it discards exactly the uncommitted work the whole record
exists to protect, so the refusal joins the same deferred list.

**The corrected premise applies to the branch refresh too.** When a `BEHIND` sibling needs
`BASE_BRANCH` merged in and its worker is still alive, the orchestrator cannot take the
branch into a worktree of its own. The row waits for that agent's end of run, or the agent is
asked to do the refresh — which is the thing it was already doing when this race was found.

## Consequences

- Nothing is instrumented. The precondition reuses 0042's two signals exactly as they are, so
  no contract spans `campaign` and `$work-issue` and no future edit to either can break the
  other's story.
- Steps 5 and 6 now assert the same fact about a dispatched agent, so the disagreement the
  issue names is gone and a future edit to one is visibly an edit to the other's premise.
- A campaign can end with worktrees still on disk and merged branches still present. That is
  the cost, and it is paid deliberately: a leaked directory is recoverable and named in the
  report, while a directory removed from under a running process is not.
- The fallback owner is the operator, and only the operator. `$clean-branches` looks like the
  standing sweep for this and is not: it enumerates candidates by `%(upstream:track)` equal to
  `[gone]`, and a campaign branch created from `origin/<base>` tracks the base rather than its
  own remote head, so the sweep never sees it. The report naming the paths is therefore the
  whole of the recovery path today. Closing that gap is a change to `$clean-branches`,
  tracked separately rather than folded in here.
- Cleanup now depends on a harness notification. A harness that does not deliver one defers
  all cleanup to the operator — the same degradation 0042 already accepted for re-dispatch,
  reached the same way.
- The branch refresh for a `BEHIND` sibling can now wait on a live worker instead of
  proceeding. Merges of *other* rows are unaffected, since each row's refresh is independent.
- A worker that hangs after its pull request merges holds one worktree, not the campaign.
  Accepted: that is the whole point of keeping `drained` where it is.
- A worktree holding untracked or modified files is skipped rather than removed, so a worker
  that leaves scratch files behind leaks its worktree even having ended cleanly. That is the
  right trade — the alternative is `--force`, which deletes the stranded work — but it means
  the deferred list is not only about live agents, and the report has to say which reason
  applied.
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
