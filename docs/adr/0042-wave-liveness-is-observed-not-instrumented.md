# 0042 — Wave liveness is observed, not instrumented

## Status

Accepted (2026-08-10)

## Context

`campaign` step 5 dispatches a wave of `$work-issue` subagents and then has nothing to
say until they report. A run in this repository lost roughly twenty minutes to an agent
that had stopped making progress and stopped reporting, and the operator — not the
orchestrator — was the thing that noticed.

The obvious repair is a staleness timer, and the obvious input to it is the age of the
branch's last commit. That input does not work. A `$work-issue` subagent is legitimately
silent for long stretches: a design phase writes no commits, an adversarial review loop
writes none between fixes, and a CI wait writes none at all. A threshold low enough to
catch a real stall fires constantly on healthy runs, and the action it triggers —
re-dispatch — is the one action that must never fire on a live agent, because two agents
working one issue produce two branches and two pull requests. The stall costs twenty
minutes; the duplicate costs a merge decision no one planned to make.

So the check needs a signal that separates *silent* from *dead*, and the filed issue
proposed one: a heartbeat file the subagent touches at each phase boundary. That proposal
has a cost the issue does not price. The toucher would be `$work-issue`, a separate skill
that exposes no such hook, so the heartbeat is not a feature of `campaign` at all — it is
an instrumentation contract between two skills, which every future edit to either has to
keep. And the file itself needs somewhere to live that both the orchestrator and a
worktree-isolated subagent can reach. Record 0027 rules out `.git/`, `$HOME`, and any
edit to a tracked ignore file, leaving `.agent/` in the working tree; the campaign
manifest already lives there and is explicitly single-writer, so the heartbeat would need
its own file per row, written by a party that writes nothing else today.

Two facts about the environment, both observed in a live campaign run rather than assumed,
make that contract unnecessary.

**Dispatched subagents run in the background and answer while they work.** The
orchestrator of that run dispatched eight subagents across two waves, messaged several of
them mid-run, received replies while they kept working, and received an end-of-run
notification as each finished. An earlier triage pass had concluded the opposite — that
dispatch is synchronous and leaves no window to poll in — and that conclusion was wrong.
There is a window, it is the whole of the wave, and a direct message into it is answered.

**`$work-issue` already publishes its phase boundaries, to a surface the orchestrator
already reads.** It swaps the issue's `status:` label at the start of work and again at
review, posts a `WORK:SCOPE` annotation before building — it does that even on the
trivial path, and its own text names that annotation a liveness signal for
`$recover-orphans` — pushes a branch and opens a pull request at ship, and posts
`WORK:REVIEW` immediately after. Those are timestamped and queryable; `github-tracking`
already carries the recipe for reading a label's application time off the timeline. None
of it is instrumentation this change adds. All of it is already produced, for other
reasons, at exactly the boundaries a heartbeat would have been touched at.

## Decision

**Wave liveness is read from two signals the run already produces, and no heartbeat file
is added to `$work-issue` or anywhere else.**

The two signals answer different questions, and neither substitutes for the other.

*Progress* is the age of the newest tracker event for a row — a `status:` label
transition, a `WORK:` annotation, a branch push, a pull request, its `WORK:REVIEW`. It
replaces last-commit age, and it is better where it matters, because it advances at phase
boundaries rather than at commits and so keeps moving through a design phase that writes
none. It is not uniformly better: the tracker says nothing at all between `WORK:SCOPE` and
`status:in-review`, so through a build that is committing, commit age is the denser of the
two. And those boundaries arrive in three clusters, not five —
start, end of build, ship — so the design phase, the build and the whole review loop each
sit inside a gap. A healthy row therefore looks stale on most polls. That is not a defect
of the signal; it is why the signal does not decide anything on its own.

*Liveness* is a direct message to the dispatched agent. A reply of any content proves the
agent is alive; nothing weaker does.

Progress decides **which rows are worth asking about**. The probe decides **what is
true**. That ordering is what makes the threshold cheap: a probe costs a live agent one
turn and changes nothing about its work, so a threshold set too low wastes a reply rather
than duplicating a pull request. The design does not need a correct number, which is
fortunate, because the correct number varies with the issue.

**Only an observed end of run authorizes re-dispatch.** Two things count: the harness's
own end-of-run notification for that agent, or the orchestrator stopping the agent through
the harness's stop control and then seeing that notification. Unanswered probes are not a
third. A row that has gone quiet, has not answered a probe across two polls, and shows no
new tracker event is a **hold** — reported in the run output, with the rest of the queue
still draining. Nothing is written down: the tracker half recomputes from live queries in
seconds, and the probe half is an observation belonging to the run that made it, so a hold
does not outlive that run and is not meant to.

**A held row keeps its in-flight state and gets no `status:` label.** This is where the
hold departs from step 6's, and the difference is the subject: a pull request held for an
operator is inert, while a held agent is one the design's own premise says is probably
still running. `github-tracking` keeps one `status:` label active, so a `blocked` written
here is removed by that agent's own next transition, leaving the manifest disagreeing with
the tracker — and a `blocked` row counts as drained, which would let the campaign end its
turn while the agent it gave up on kept working toward a pull request nobody was waiting
for.

**The operator's answer to a hold is what reaches the stop control.** That is the entry
condition, and without one the second route above would be an authorization nothing could
ever trigger, leaving automatic re-dispatch to fire only on a harness-reported crash and
never on the wedged agent this was filed against. Putting the operator there also puts the
judgement where the destructive half is: stopping a merely slow agent discards whatever it
had not committed, and no threshold this record could name distinguishes slow from wedged
— that is precisely what the probe already failed to do by the time a hold exists.

**A re-dispatch resumes rather than restarts, and carries the partial work by reference.**
The branch holds the committed work; the successor is handed its name, an explicit reuse
decision, and the last phase the tracker showed — not a pasted diff, which is bulky going
in and stale on arrival. Two cases are not resumable that way and are called out rather
than papered over. A row with no branch at all died before one existed and is dispatched
fresh. And the dead agent's worktree still holds the branch checked out, so the successor
cannot add its own worktree on that path until the orchestrator reclaims it — handing over
the path or removing it — which is also the only window in which the uncommitted edits
stranded there can be read. Artifact reconciliation runs before any of this, because a
dying agent may have pushed a branch or opened a pull request the manifest has not
recorded.

## Consequences

- The check ships inside one skill. Nothing in `$work-issue` changes, so no contract
  spans the two skills and no future edit to either can silently break the other's
  liveness story.
- The signal is as reliable as the tracker, which is where campaign state already lives —
  and it survives the orchestrator's own restart, because it is queried rather than
  remembered. A heartbeat file in a subagent's worktree would not have.
- Nothing is written. There is no new state file, no new manifest column, and no new
  ignore-path question, so record 0027's constraints are satisfied by not engaging them.
- A probe consumes a turn of a live agent's run. That is the price of the discriminator
  and it is paid only on rows that have gone quiet.
- The poll needs a trigger of its own when the orchestrator has nothing else in hand —
  serial dispatch, or the tail of a wave whose healthy rows have all finished. Those are
  the cases the filed stall actually occurred in, so leaving the poll to ride on other
  rows' events would have reproduced it. The orchestrator waits on the outstanding rows
  from a background task instead, which is what the standing rule against foreground sleep
  loops already prescribes for anything long.
- A hung agent that still answers messages reads as alive and will not be re-dispatched.
  This is deliberate. The alternative is a heuristic that decides an answering agent is
  dead, which is the duplicate-pull-request failure by a subtler route; a genuinely wedged
  agent surfaces as a row whose progress never advances, and the operator is watching the
  table that says so.
- The bar for re-dispatch is high enough that a real death reaches the operator as a hold
  before anything is stopped or re-dispatched. Accepted, and it is most of the repair on
  its own: the failure this was filed against is a stall nobody noticed, and a table
  naming the stalled row is the noticing.
- A future harness that does not deliver end-of-run notifications loses automatic
  re-dispatch entirely and keeps everything else — the poll still runs, the probe still
  discriminates, and every candidate becomes a hold.

## Considered & rejected

- **A heartbeat file the dispatched agent touches at each phase boundary**, as the issue
  proposed. Rejected: it is an instrumentation contract between two skills, bought to
  observe boundaries that are already published to the tracker for other reasons. It also
  answers the weaker question — a heartbeat proves the agent reached a boundary, not that
  it is alive now, so a stall between two boundaries looks identical to death, which is
  the discrimination the issue asks for and the one a heartbeat cannot make.
- **Last-commit age alone.** Rejected by the issue itself, and correctly: design phases,
  review loops, and CI waits all write no commits.
- **The dispatched agent's process state.** Rejected as unreachable: a subagent is a
  harness construct, not a process the orchestrator can name, and the harness already
  exposes the fact through the end-of-run notification this record uses instead.
- **A column in the campaign manifest holding each row's last heartbeat.** Rejected: the
  manifest is slug-keyed to one selector on one machine, is single-writer, and is
  gitignored, so it is the wrong channel for state about a party that is not its writer —
  and the poll's inputs are live queries that a stored copy could only go stale against.
- **Re-dispatch on an unanswered probe, without an observed end of run.** Rejected: it
  restores exactly the duplicate-pull-request risk the whole design exists to avoid, in
  exchange for automating a case the operator is already looking at.
- **A tuned per-phase staleness threshold** — one number for design, another for review,
  another for a CI wait. Rejected as unnecessary once the probe is what decides: the
  threshold only chooses when to ask, and asking is cheap.
