---
name: work-issue
description: "Implement a GitHub issue end to end through scoping, feature-branch setup, design, TDD, adversarial review, threat scan, simplification, pull-request creation, CI, merge handoff, and cleanup. Use when asked to work, implement, or resolve a specific GitHub issue with the repository's full workflow."
---
Implement the supplied GitHub issue end-to-end on a feature branch, following
this repo's conventions in `AGENTS.md`, and drive it to a CI-green,
mergeable PR ready for the user to merge.

Work the steps in order. Keep the guardrails green at every commit. Do not advance
past a red guardrail, unresolved `$challenge` finding, dirty working tree surprise,
or ambiguous user-facing design decision.

> **Single continuous task.** This skill is one task from preflight through
> cleanup. It delegates to sub-skills (`$preflight`, `$design`, `$build-tdd`,
> `$review-loop`, `$simplify-changes`, `$ship-pr`, `$merge-cleanup`), each of which is also
> independently runnable. Intermediate checkpoints — a `$challenge` verdict, a
> passing guardrail, a green CI run, a `$threat-scan` verdict — are **not** turn
> boundaries. Do not end your turn at a checkpoint. End your turn only when (a) the
> PR is green and mergeable (or merged, if the operator authorized it — step 8),
> or (b) you hit a genuine blocker you have named **and parked per *On a Blocker*
> below** — naming it is half the obligation; the issue must also carry the state.
> This matters most when you are a background subagent: reaching `approve` in a
> review loop means *proceed to the next step now*, not *stop and wait*.

> **Context checkpoints between phases.** `$work-issue` has natural seams
> (design → build → review → ship) where earlier raw context — brainstorm
> transcripts, `$challenge` payloads, TDD red/green output — stops being
> load-bearing, because the spec, plan, ADR, and findings files already *are* the
> durable distillate. At each seam, before advancing: **(a)** ensure the checkable
> facts a resume needs — the branch name, `BASE_BRANCH`, the guardrail commands,
> the current step, and any open findings — are written into a durable artifact
> (the plan, the campaign manifest, or a scratch note); and **(b)** as a reminder,
> that the phase's spec/plan/findings hold every design decision, not just the
> transcript. If auto-compaction fires past this point, those artifacts are the
> only recovery path. Do **not** run `context compaction` proactively; just keep them
> complete. If the *operator* compacts manually, suggest steered focus text —
> *keep:* branch, `BASE_BRANCH`, guardrail commands, current step, open findings;
> *drop:* resolved review iterations, tool output.

## 0. Preflight

Run `$preflight` to discover the repo environment: `BASE_BRANCH`, guardrail
commands, working-tree state, gh authentication, and parallel-run context.

## 1. Scope the Issue

Run `gh issue view <issue-number> --json title,body,labels,comments` and follow linked
issues, PRs, specs, or commits.
Restate the requirement and acceptance criteria in your own words before touching
code. Ask the user only if something is genuinely ambiguous **and** the answer
changes the design; otherwise state your assumption and proceed.

Also classify the work:

- **Trivial bugfix:** all acceptance criteria are clear; no API, schema, auth,
  permission, concurrency, migration, dependency, persistence, or external-service
  behavior changes; touches one or two files; no new public contract.
- **Governed small change (`governed-small-change`):** one accepted decision governs
  every changed contract and normative behavior; the acceptance criteria are explicit
  and testable; no design-changing ambiguity remains; the work is one independently
  testable slice with no cross-task sequencing or decomposition; and implementation
  introduces no architecture, schema, dependency, persistence, concurrency,
  authentication, migration, or external-service behavior.
- **Non-trivial change:** anything else.

<!-- SCOPE-RULE:governed-small-change -->
Classify as governed-small-change only when one accepted decision governs every changed contract and normative behavior.
Require explicit testable acceptance criteria, no design-changing ambiguity, and one independently testable slice with no cross-task sequencing or decomposition.
Revalidate the decision reference, decision kind, accepted status, and governed behavior when the abbreviated path is consumed.
Missing, superseded, non-accepted, conflicting, incomplete, or no-longer-governing evidence returns to SCOPE CHECKPOINT and full design.
<!-- SCOPE-RULE:END:governed-small-change -->

Only trivial bugfixes and verified governed small changes may skip step 3. The governing
decision must be a stable reference whose repository-defined status and supersession state
can be checked independently. Record its reference, decision kind, authoritative accepted
status, and the behavior or contract it governs; a label or caller-selected subtype is not
evidence.

**Adopt an existing `$scope` report.** If the operator ran `$scope <issue-number>` in this
session, its report already carries blast radius, risk flags, complexity (S/M/L), and
the decompose verdict — adopt those fields for the classification above and for step 3's
`WORK:SCOPE` annotation rather than re-deriving them. Re-check them against the issue
body first: `$scope` writes nothing, so its report is a session artifact that may predate
later comments. With no `$scope` report in the session, derive the fields here — a
dispatched subagent never inherits one, so this is the ordinary path.

**Track state (github-tracking skill).** Ensure-create the `status:` labels (skill recipe),
then set this issue to `status:in-progress` (single-active swap, removing any other
`status:` value). If ensure-create fails, stop with its message rather than proceeding
label-less.

<!-- SCOPE-ORDER:work-frozen -->
## Frozen scope charter

Freeze the complete external authority before design. Set `interaction: interactive` when
a human invoked this run in the active turn. Set `interaction: unattended` only when an
orchestrator or background task explicitly says no human is reachable. Nesting never
changes this root value.

Record all eight fields in the issue's `WORK:SCOPE` annotation:

<!-- SCOPE-RULE:scope-identity -->
Use the issue URL plus a unique annotation token as the pre-publication scope identity.
<!-- SCOPE-RULE:END:scope-identity -->

<!-- SCOPE-RULE:public-scope-comment -->
Before posting any GitHub annotation, keep only public-safe authority labels; omit secrets and host data.
If authority cannot be summarized safely, do not post or log its raw value.
An unattended root may post only a generic public-safe WORK:TRAJECTORY notice without charter values.
<!-- SCOPE-RULE:END:public-scope-comment -->

- `scope identity`: the issue URL plus that unique annotation token;
- `outcome`: the requested outcome;
- `completion criteria`: each criterion and its source;
- `provenance`: the source of every outcome, criterion, and later user decision;
- `exclusions`: explicit exclusions and their owners, or an explicit empty value;
- `surface`: permitted change surface and direct dependencies;
- `ambiguities`: unresolved design-changing ambiguities, or an explicit empty value;
- `interaction`: the root value established above.

Also retain the tracking metadata: blast radius, risk flags, complexity (`S`/`M`/`L`),
decompose verdict, and selected classification. A `governed-small-change` additionally
retains the decision reference, decision kind, accepted status, governed behavior, and
the explicit acceptance criteria. Read those fields back with the eight charter fields
before proceeding.

Minimize every public GitHub annotation to the authority needed for its fields. Use
public-safe source labels for provenance instead of copying private source text. Never
include secrets, authentication headers, host-specific paths, hostnames, IP addresses, or
private internal details. Do not log an unsafe answer. When it cannot be summarized without
disclosure, return to `SCOPE CHECKPOINT` and leave `WORK:SCOPE` unposted; an unattended root
may post only a generic public-safe parked notice with no charter values or raw answer.

Every normative guarantee must trace to this charter, a later explicit user decision, or
an unavoidable consequence of satisfying a sourced criterion. The workflow and the
artifact it produces cannot authorize their own scope. More review authorizes more
scrutiny, not more scope.

<!-- SCOPE-ORDER:work-checkpoint -->
### SCOPE CHECKPOINT

Before freezing, return here when an omission or conflict could change a charter field or
normative guarantee. In an interactive run, ask one design-selecting question at a time,
record the answer and provenance, then freeze the complete charter. After freezing, a
design-changing answer ends the current design cycle and re-freezes the charter before a
new cycle starts. Missing, incomplete, or unresolvable fields never fall back to a spec,
ADR, plan, or other generated artifact.

<!-- SCOPE-ORDER:work-unattended -->
### Unattended parking

When the root interaction is unattended, do not answer a design-changing question on the
caller's behalf. Post a public-safe `WORK:TRAJECTORY`, set `status:needs-human`, and stop
before design. If checkpoint data is unsafe, the trajectory contains only a generic parked
phase and request for human input; it never contains charter values or the raw answer.

Mint the annotation token once before posting and include it in the comment. Capture the
returned comment URL as the annotation's location, not its identity. Read the posted comment
back and verify the token and all eight fields before continuing. It is also the liveness
signal `$recover-orphans` reads, so post it for a trivial bugfix that will skip design.

## 2. Branch

Fetch the latest remote state. Sync `BASE_BRANCH` to `origin/BASE_BRANCH`, then
create `feat/<short-slug>-<issue-number>` off it. Never work on the default branch.

**Worktree placement.** If repo instructions require an isolated worktree (or you
are a parallel agent that must not share a working tree), create it **outside the
repo tree** at a sibling path such as `../<repo>-worktrees/<branch>`, and `cd`
there as your first action. Never nest a worktree inside the repo (not under
`.codex/`, not any subdir) — whole-tree tooling (linters, type checkers, test
discovery, search) will walk it and fail your commit on another agent's in-flight
code. If the harness's built-in worktree isolation would place the worktree inside
the repo, do not use it; run `git worktree add <external-path>` yourself.

If the repo already has a branch for this issue, ask before reusing it unless the
issue or PR explicitly names that branch.

<!-- SCOPE-ORDER:work-abbreviated -->
### Governed small change path

Immediately before using the abbreviated path, resolve the governing decision again and
confirm its kind, accepted and non-superseded status, claimed governed behavior, and fit
against the live issue criteria. Confirm the work is still one independently testable
slice and no excluded decision or ambiguity has appeared. A failed check returns to
`SCOPE CHECKPOINT`; re-freeze the complete charter and run step 3. Do not automatically
reselect the abbreviated path in that design cycle.

<!-- SCOPE-RULE:governed-direct-build -->
A governed-small-change proceeds from verified WORK:SCOPE directly to build-tdd without a new spec or plan.
<!-- SCOPE-RULE:END:governed-direct-build -->

<!-- SCOPE-ORDER:governed-proof -->
The first executable action on the abbreviated path is the focused failing test in step 4.
<!-- SCOPE-ORDER:governed-elaboration -->
Optional design elaboration may follow that proof but is not a prerequisite.

<!-- SCOPE-RULE:post-build-controls -->
The abbreviated path retains branch review, simplification, repository guardrails, PR creation, CI, and merge handoff.
<!-- SCOPE-RULE:END:post-build-controls -->

<!-- SCOPE-ORDER:work-design -->
## 3. Design

Pass the frozen charter to `$design` exactly as follows:

<!-- SCOPE-CARRIER:work-issue-to-design -->
interaction: <unchanged root value>
scope identity: <external scope identity, never reviewed target>
outcome: <frozen external outcome>
completion criteria: <frozen external completion criteria>
provenance: <external source for every outcome, criterion, and user decision>
exclusions: <frozen external exclusions>
surface: <frozen permitted surface>
ambiguities: <frozen ambiguity list>
<!-- SCOPE-CARRIER:END:work-issue-to-design -->

Run `$design <issue-number>` to write the spec + ADR, adversarial-review the spec,
write the implementation plan, and adversarial-review the plan. Skip only for a
trivial bugfix or a governed small change that passed the revalidation above.

**Durable artifact:** the spec, ADR, and implementation plan written by
`$design` (see that skill for their exact paths — the ADR lives under
`docs/adr/`, not with the plan). Context checkpoint before step 4 (see the callout
above): brainstorm transcripts and spec-review payloads are droppable once these
hold the design.

## 4. Build With TDD

Run `$build-tdd` to implement the plan using test-driven development and run the
guardrail suite. Pass the plan path if one exists.

**Durable artifact:** the committed code and tests, plus the plan's completed
tasks. Context checkpoint before step 5: the branch name and guardrail commands
must be recorded somewhere durable (manifest or a note) — TDD red/green output is
droppable.

## 5. Adversarial-Review the Branch

**Track state.** Set the issue to `status:in-review` (single-active swap).

Run `$review-loop --base <BASE_BRANCH> Focus on auth, permissions, data loss
or corruption, rollback, idempotency, races, empty or malformed inputs,
degraded dependencies, compatibility, migrations, observability, and whether
the chosen approach is simpler or safer than viable alternatives.`

Address every defensible finding. Commit after each accepted fix.

**Security pass.** When the branch diff is security-relevant, also run
`$threat-scan` and disposition its findings on the same terms — fixed, or owned
by a tracked deferral (a deferral record where the repo keeps them, otherwise a
tracker issue). It is non-blocking: a `needs-attention` verdict is work to do,
never a reason to park the issue.

Dispatch it the way `$review-loop` dispatches its reviewer: in a **subagent**,
with `--json --out <path>` to a scratchpad path outside the repo tree, invoked
as `$threat-scan --json --out <path> --base <BASE_BRANCH>`. Invoked bare it
returns full markdown inline, which puts a findings payload into this skill's
context at step 5 of 8 — the cost `$review-loop`'s dispatch exists to avoid.

Two properties that dispatch depends on, both cheaper here than in
`$review-loop` because this is single-shot and needs no stability across
iterations:

- **The path must be unique to this run.** Embed the issue number and branch
  name — a fixed filename collides under `$campaign`, which runs waves of up to
  five `$work-issue` subagents in parallel, each reaching this step. On a
  collision one issue's security findings are read and dispositioned against
  another's branch, silently. Assert the `run_id` in the compact object matches
  the artifact's before acting on it; that assertion is the only detector.
- **Open the artifact when `findings_count > 0` *or* `suppressed_count > 0`.**
  A non-zero `suppressed_count` on an `approve` verdict means an accepted ADR
  silenced a security finding — the one case the verdict cannot show you. Record
  any suppression in the review summary whatever the verdict.

The diff is security-relevant when it does any of the following. Judge it by
reading the changed files, not by the issue's description of itself:

- **changes what an untrusted actor can reach or cause** — a new or widened
  entry point (route, handler, CLI argument, environment variable, config key,
  webhook, queue consumer), or a change to who may call an existing one;
- **touches authentication, authorization, session, or tenancy logic** —
  including adding an entry point beside siblings that carry such a check;
- **handles a secret** — reads, stores, forwards, logs, or scopes a credential,
  token, or key, or edits CI config that does;
- **parses or deserializes input it did not produce** — request bodies, uploaded
  files, archives, or any format that constructs objects while decoding;
- **builds a command, query, path, URL, or template from a value** that is not a
  literal in the same file;
- **widens a permission grant** — a workflow's permission grant (ADR 0017), a CI
  token scope, a sandbox or guardrail exemption;
- **changes a dependency, a lockfile, or a pinned CI action reference**;
- **alters file modes, network exposure, TLS or certificate handling, or a
  security-relevant default**.

When none apply, skip the pass. When you genuinely cannot tell, run it — a
dispatched scan costs one subagent and returns a compact object, so the
asymmetry favours running. Do not run it on every diff to be safe: a pass that
reports nothing on everything is one the operator learns to skim, which costs
more than the runs saved.

Run it **after** the `$review-loop` fixes above, so it scans the code that will
ship rather than a state you have already left. A security fix is rarely a pure
rename, so if closing a finding changes behavior, re-run `$review-loop` on the
result — the loop's own review did not cover the fix you just made.

**Cap that alternation at one round trip.** `$review-loop` bounds its own
iterations and cycles, and `$threat-scan` is single-shot, but neither cap covers
the oscillation *between* them: each re-entry to the loop starts a fresh count.
So allow at most one `$threat-scan` → `$review-loop` → `$threat-scan` round
trip. If a second would be needed, **do not re-enter and do not park** — carry
on to step 6 and record the unresolved findings as open in the review summary,
so they reach `WORK:REVIEW` and the PR rather than stalling the run. The cap is
a reporting boundary, not a blocker; an unattended run has no one to notice it
ping-ponging, and no one to un-park it either.

Record the verdict alongside the review summary either way, including
`security: not triggered` when it did not run, so the `WORK:REVIEW` annotation
in step 7 says which arms ran rather than leaving a reader to infer it.

`$threat-scan` is this pipeline's own pass, and it is a weaker instrument than
the built-in `/security-review` — which a model cannot invoke at all, since a
built-in expands client-side only when a human types it (ADR 0023). Where an
operator wants the built-in, `$merge-cleanup`'s hand-off is where a human is
reliably present to run it.

**Durable artifact:** the `$review-loop` findings file (superseded each iteration)
and your fix commits. Context checkpoint before step 7: open findings and the
branch/guardrail state must be captured — resolved review iterations are droppable.

## 6. Simplify

Run `$simplify-changes` to apply reuse, simplification, and efficiency cleanups to the
branch diff. Re-run the guardrail suite and commit the result. Quality only —
do not reopen settled design decisions. The step-5 review covered the
*pre-simplify* code, so if `$simplify-changes` makes any change that could alter behavior
(not a pure rename/format), re-run `$review-loop` (or at minimum `$challenge`) on
the simplified diff before shipping — guardrails alone only catch what the tests
already assert.

## 7. Ship It

Run `$ship-pr <issue-number>` to push the branch, create the PR, and drive it to
green CI and mergeable state.

**Annotate (github-tracking skill).** The step-5 review produced a verdict, findings count,
iteration count, and `$threat-scan` verdict — retain that compact **review summary** as a
durable artifact (the manifest or a scratch note); only the verbose per-iteration findings
file is droppable. Immediately after `$ship-pr` creates the PR, post a `WORK:REVIEW` comment
on the PR from that summary. `$ship-pr` itself does not post it.

## 8. Hand Off or Merge, Then Clean Up

Run `$merge-cleanup` to hand off (default) or merge (if operator-authorized),
then clean up branches and worktrees.

## On a Blocker — Park the Issue (github-tracking skill)

Reachable from any step above. A named blocker is not a clean exit until the issue
records it, in this order:

1. **Post the `WORK:TRAJECTORY` note first** — the parked phase (which step), the live
   branch and PR if either exists, guardrail status, and exactly what a human must
   decide or supply. The skill's exit-edges rule requires the note *before* the label,
   so an issue is never parked without a record of where it parked.
2. **Then set the label** (ensure-create it first, same recipe as step 1; single-active
   swap — the one `gh issue edit` call removes every other `status:` value, whichever
   the issue currently carries):
   - **`status:blocked`** — an external dependency: an unmerged upstream PR, an absent
     credential or service, a decision owned by someone not in this turn.
   - **`status:needs-human`** — the pipeline itself cannot proceed and a human must
     diagnose: a guardrail that cannot be made green, a `$review-loop` finding you
     cannot resolve or reject, a design question only the operator can settle.

Without this the issue keeps a live-looking `status:` and nothing flags it. Do not count
on `$recover-orphans` to catch it: its reset requires **no** PR *and* **no** matching
branch, and a parked `$work-issue` almost always left a branch — so the sweep's likely
action is to re-label the issue to match its PR's state, which reads as *in flight*. It
also fails closed on an empty label timeline, and it is a between-runs reconciler a human
must invoke. The label is the only thing that says *parked* rather than *in flight*.

**If a `$campaign` dispatched you**, you still own this write — it is your issue's
transition edge, and the orchestrator does not duplicate it. Report the blocker in your
completion report as well, so the orchestrator can record its manifest row and keep
draining the rest of the queue.
