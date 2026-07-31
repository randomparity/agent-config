---
name: campaign
description: >-
  Orchestrate a set of GitHub issues until each is closed as already fixed or
  resolved by a merged pull request, including triage, dependency planning,
  per-issue execution, serial merging, and newly discovered work. Use when
  asked to run a campaign, clear an issue set, or drive a batch of issues to
  done.
---
Drive a **set** of GitHub issues to done — every issue either closed (already
fixed) or merged (fixed by a PR) — reusing `$work-issue` per issue rather than
reimplementing the lifecycle. Follow this repo's conventions in `AGENTS.md` /
`AGENTS.md`.

> **Single continuous task.** This skill is one task from resolving the issue
> set through the last merge. It delegates to sub-skills (`$preflight`,
> `$work-issue`, `$merge-cleanup`), each of which is also independently runnable.
> Intermediate checkpoints — a triage verdict, a green CI run, a merged PR — are
> **not** turn boundaries. Do not end your turn at a checkpoint. End your turn
> only when (a) the work queue is empty (every original and newly-filed in-scope
> issue is closed or merged), or (b) you hit a **global** blocker you have named
> (dirty tree, missing auth — something that stops the whole batch). An
> **issue-local** blocker (one issue's fix can't pass guardrails) is not a
> turn-ender: mark that issue blocked and keep driving the rest of the set — see
> step 8.

> **Authorization.** Invoking `$campaign` **is** authorization to auto-close
> issues you have shown are already fixed and to self-merge green + mergeable PRs
> — report each such action as you take it. This authorization stays at the
> orchestrator: **never** propagate merge authorization to a per-issue subagent.
> Each `$work-issue` run stops at a green + mergeable PR; the orchestrator merges.

Work the steps in order. Keep the guardrails green at every commit. Do not
advance past a red guardrail, a dirty-tree surprise, or an ambiguous user-facing
design decision.

## 1. Resolve the Issue Set

Parse the user-supplied selector into a set of issue numbers. Support, in any combination:

- **Explicit numbers** — `992 994 1001`.
- **Ranges** — `992-997` (inclusive; resolve each number, skip any that do not
  exist as open issues).
- **Natural-language selector** — e.g. `open issues labeled bug`, resolved with
  `gh issue list --json number,title,labels` (plus `--label`, `--state`,
  `--search`, `--limit` as appropriate).

On every path, drop `epic`-labeled issues from the resolved set (report the drop) —
epics are PRD holders outside the `status:` machine (github-tracking rule); their
sub-issues are the workable units. The explicit-numbers and range paths must fetch
labels for the resolved numbers to evaluate this (the NL path already has them).

Any trailing free text after the selector is **completion notes** — context on
what "done" means for this batch; carry it into triage and PR bodies.

**Initialize the campaign manifest** — the single source of truth for this run —
**find-or-create, never blind-create**. Key it on a **selector identity stable
across runs**, not on the resolved membership (which drifts for NL/query selectors
as issues open and close — keying on it would change the slug every run and never
reattach). Normalize the *selector*: for explicit numbers/ranges, the sorted
deduped set of **requested** numbers (the literal range expansion, taken before
the "skip issues that don't exist" filter — so closing a member later does not
change the slug); for an NL/query selector, the lowercased, whitespace-collapsed
query string. For a selector that **mixes** shapes (step 1 allows any
combination), concatenate the two normal forms deterministically — sorted
requested numbers, then the normalized query — so a mixed selector has one total,
reproducible normal form. The slug is a short hash of that normal form, so `10 11`
and `11 10` map to one manifest, the same NL query reattaches across runs even as
its matches change, and the filename stays bounded regardless of set size. Store
the full normal form in the manifest (`Normalized-selector`), because a short hash
can collide. Use `.codex/campaigns/<slug>.md`. Routing on the existing file — on
any match, **first confirm the loaded manifest's `Normalized-selector` equals this
run's**; on mismatch it is a hash collision, so fall through to a disambiguated
filename (`<slug>-2.md`, …) rather than resuming a foreign campaign:

- **No file** → create and populate it (below), with header `Status: active`.
- **File with `Status: active`** → **resume**: load it, skip re-initialization,
  and do **not** overwrite any non-`pending` row (that wipes the progress step 3
  reconcile reads back). For a natural-language / query selector, reconcile the
  **live** resolved set against the loaded queue — enqueue issues that now match
  but aren't in the queue; never treat the first-run snapshot as canonical. If the
  incoming completion notes differ from the stored ones, surface the difference and
  confirm which intent governs rather than silently keeping the first run's (they
  drive triage and PR bodies).
- **File with `Status: complete`** → the prior campaign under this selector
  finished. Do **not** reattach (that silently no-ops). Archive it under a unique
  name (`.codex/campaigns/<slug>-done-<UTC-timestamp>.md`, timestamp-suffixed so
  two same-day completions don't collide) and create a fresh manifest.

On create, populate: the resolved queue with per-issue status, the completion
notes, the completion condition (**every queued issue closed or merged**), and
placeholders for the `$preflight` findings (step 2) and step-4 assignments.

**Keep the manifest out of git without relying on the target repo's `.gitignore`.**
`$campaign` runs against arbitrary repos, and many **track** `.codex/` — there
the manifest would land in a per-issue PR diff or trip `$preflight`'s dirty-tree
stop. So ensure `.codex/campaigns/` is in `.git/info/exclude` (per-clone, local,
never committed, independent of the repo's tracked `.gitignore`) — idempotent: add
it if absent, on both create and resume, so a resume in a fresh clone is covered
too. If the path is somehow still not ignored (`git check-ignore -q` fails), stop
with that as a named blocker rather than proceeding to pollute a PR.

Discipline: the **orchestrator is the only writer** — every step reads/updates the
manifest instead of re-deriving state, and subagent prompts reference manifest
facts **by value** (copied into the prompt), never ask a subagent to write it.
Write it atomically (write a temp file, then rename) on every update, since the
orchestrator rewrites it at nearly every step and a crash mid-write must not leave
a truncated table. On load (step 3), validate it parses; if it is unparseable,
stop with a named blocker rather than resuming on a partial queue. the task plan
mirrors the manifest for live progress display only; the manifest, not the task plan,
is what a fresh-session resume reads.

The manifest schema:

```markdown
# Campaign: <slug>  (started <YYYY-MM-DD>)
- Status: active            # flip to `complete` in step 8; gates reattachment
- Selector: <raw selector>
- Normalized-selector: <the normal form the slug hashes; reattach must match this>
- Completion notes: <trailing free text, or "none">
- Completion condition: every queued issue closed or merged
- BASE_BRANCH: <filled by step 2>
- Guardrail commands: <filled by step 2>
- ADR-index coupling: <filled by step 2; `coupled` | `not coupled` | `no index`>

## Queue
| Issue | Status | Branch | Verdict | ADR/migration # | File scope | Wave | PR | Outcome |
|-------|--------|--------|---------|-----------------|------------|------|----|---------|
| #NNN  | pending| —      | —       | —               | —          | —    | —  | —       |

## Outcomes log
<orchestrator appends one line per close/merge/block>
```

The `Branch` column records each in-flight issue's branch so step-3 resume can
check it out without guessing. Statuses progress
`pending → triaged → in-flight → merged | closed | blocked`.

## 2. One-Time Environment Discovery

Run `$preflight` **once** for the whole batch to capture `BASE_BRANCH`, the
guardrail commands, gh authentication, working-tree cleanliness, and — where the
repo keeps an ADR index — whether a gated check couples a record to its row
(step 4). Record `BASE_BRANCH`, the guardrail commands, and that coupling verdict
into the manifest (step 1); step 6 branches on it and a resume never rediscovers
it. On resume, if the manifest already carries them, read them from it and skip
re-running `$preflight` (re-confirm gh auth and a clean tree only). Stop on a
named blocker (dirty tree, missing auth) before touching any issue.

## 3. Triage Each Issue — Does the Bug Still Exist?

**Reconcile prior-run state first.** This skill must survive being resumed
after an interruption. On resume, **read the manifest (step 1) before anything
else** — it holds the queue, per-issue status, `BASE_BRANCH`, guardrail commands,
and step-4 assignments, so nothing below gets re-derived. For each queued issue,
before triaging, check for leftover artifacts from an earlier run and route by
state (`$work-issue` has no mid-lifecycle resume entry point, so name the branch
explicitly):

- **Already-closed in-scope issue** → done; drop it from the queue without
  re-closing.
- **`status:` label already set** (github-tracking skill) → read it first: an issue carrying
  an in-flight `status:` (`in-progress`/`in-review`/`awaiting-merge`) is already in the
  pipeline — adopt its state instead of re-triaging. Treat a **closed** issue as done
  regardless of any lingering `status:` label (closed-state is authoritative). Do not run
  `$recover-orphans` while this campaign is actively dispatching — it is a between-runs
  reconciler; point stuck issues at it after the campaign drains.
- **Existing PR that is green + mergeable** → mark it **ready-to-merge** and
  carry it into the step-4 plan table; step 6 merges it. Do not merge inline here
  and do not start a fresh `$work-issue` — reconcile records state, it does not
  execute writes.
- **Persisted step-4 assignments exist in the manifest** (from an earlier run) →
  read them back and reuse the ADR/migration numbers and file scope already
  recorded; do **not** let step 4 re-derive them, or a resumed branch may get a
  number different from the one it already committed.
- **Existing branch/PR that is incomplete** (no PR, or PR not yet green) →
  **dispatch a subagent**; `$work-issue` has no mid-lifecycle entry, so it re-runs
  from the top. The reliable default is to **delete the branch and restart cleanly**
  (its commits were never merged, so nothing final is lost). Reuse the existing
  branch only when its work is expensive to regenerate — then instruct the subagent
  to answer `$work-issue`'s branch-reuse prompt with "reuse" (it re-derives the same
  deterministic `feat/<short-slug>-<n>` name and finds the branch), accepting that a
  from-the-top re-run may redo phases and stack commits. State which path you took.
  Like every fix it runs in a subagent (step 5), never inline.
- **No artifacts** → the normal path: triage it (below), then fix (steps 4–5) if it
  is not a close-candidate.

For each remaining queued issue, **dispatch one read-only triage subagent** rather
than reading the issue, its linked PRs and commits, and the codebase inline —
read-heavy fan-out is exactly what subagents are for, and it keeps N investigations
out of the orchestrator's window. Triage does no writes, so the subagents need no
worktrees and can run in parallel (waves of up to 5). Each subagent prompt names the
issue, directs it to **investigate the issue body, its linked PRs and commits, and
the current code** to decide whether the bug still exists, and **ends with a
structured-verdict contract** (a triage-specific extension of the shared subagent
report contract in `AGENTS.md`) — return only:

- **verdict** — `close-candidate` | `fix` (with the sub-type `trivial-bugfix` |
  `non-trivial`),
- **evidence** — the citations behind it (`file:line`, commit SHA, PR number),
- **rationale** — ≤300 tokens of *why*, so step 4 can author the public close
  comment (and the fix-model choice) from the subagent's own finding rather than
  re-investigating,

and nothing else (no pasted issue bodies, diffs, or file contents). The `fix`
sub-type is the complexity estimate that drives fix-time model selection (step 4);
it is N/A for `close-candidate`. `ready-to-merge` is **not** a triage return — it is
a reconcile-only manifest state (an existing green + mergeable PR, above). The
orchestrator records each returned verdict in the manifest (`Verdict` column) and
builds the step-4 plan table from them — one structured verdict per issue, never raw
reads. Reconcile-routed states (`ready-to-merge`, already-closed, restart-clean)
live in the `Status` column, not `Verdict`; the step-4 plan table reads across both.

Pick each triage subagent's model at dispatch from the signals available then —
title, labels, issue length (mirroring `$build-tdd`'s policy): clearly mechanical →
a cheaper fast model; ambiguous, wide-surface, or thin signal → default to the most
capable model, since difficulty is what the subagent is being sent to determine and
the model can't change mid-run.

The verdict classifies the issue:

- **`close-candidate`** — the subagent judged the code already resolves it and cited
  the fixing code/PR. Because closing is public and irreversible, the orchestrator
  still **confirms every close-candidate against ground truth with the
  `bug-claim-verifier` agent** (or `$challenge` on the "already-fixed" claim) before
  it is closed — this verification is unchanged. If it confirms, keep the verdict; if
  inconclusive, route to the fix path. Do **not** run `gh issue close` here — closes
  execute together in step 4, after the plan table makes every planned close visible.
- **`fix`** — its sub-type (`trivial-bugfix` vs `non-trivial`) drives fix-time model
  selection (step 4). A `trivial-bugfix` from a cheap-model triage is a floor, not a
  ceiling: step 4 may escalate the fix model if the fix proves subtler than triage
  judged.

## 4. Plan the Fix Batch

Count the issues still needing fixes after triage. **Every fix runs in a
subagent** — the orchestrator never runs a `$work-issue` lifecycle inline, which
would pull the whole design/TDD/review/CI transcript into its window and never
release it (the largest context sink in the system). The only decision is **wave
size**:

- **Wave size 1 (serial)** — dispatch one subagent, merge its PR (step 6), then
  the next. Use it for **coupled** issues: those whose step-4 file scopes overlap,
  or that have an ordering dependency (one's fix builds on another's merge). Serial
  runs need no worktree isolation beyond the usual one-branch-per-issue rule.
- **Waves of up to 5 (parallel)** — for **independent** issues: disjoint file
  scopes, no ordering dependency (step 5).

Record each issue's dispatch group **and order** in the manifest (`Wave` column) —
`s1`/`s2`/… for serial issues (the ordinal fixes the merge order that coupled,
dependency-ordered issues require), or `w1`/`w2`/… for parallel wave membership —
so a resumed run reconstructs both instead of re-deriving from a vague criterion,
the same file-based discipline as the ADR assignments.

**Either way**, pre-scan `docs/adr/` and any migration directories and **assign
each issue its own ADR/migration numbers** and a **best-effort file scope** —
needed even serially, so a crashed issue that is re-dispatched (step-6 recovery)
reuses the same number instead of grabbing a new one. Assigning up front prevents
duplicate ADR numbers and migration-filename collisions. It does **not** prevent
conflicts in a hand-maintained ADR index — git conflicts on adjacent insertions, so
rows 0453 and 0454 collide despite being disjoint, which is why subagents leave those
rows to step 6 — unless CI gates the index, which inverts the split; step 6 carries
both branches. File scope is a *hint*,
not a guarantee: which files a fix touches is often only known once it is designed,
so two fixes can still both need a shared registry/index/lockfile (e.g.
`install.sh`'s `CURATED` list). The real collision guard is the step-6 serial-merge
rebase, which reconciles any overlap that surfaces as `BEHIND`/`DIRTY`. Direct each
subagent to report when its fix must touch a file outside its assigned scope, so
you can re-plan rather than discover it at merge.

**Persist the assignments into the manifest** (step 1), not working memory or
the task plan. Fill each issue's `ADR/migration #` and `File scope` columns. A genuine
resume (fresh context after a crash or summarization) loses working memory; the
step-6 recovery path and the step-3 read-back both read these from the manifest.
Re-deriving them by re-scanning `docs/adr/` on resume can hand an in-flight branch
a *different* number than the one already committed to it, causing the exact
collision the assignment prevents (`AGENTS.md`: "prefer file-based state for
transparency and portability").

Present the triage/plan table — issue → **close-candidate** / **ready-to-merge**
(from reconcile) / **fix** (with its wave size), with assigned numbers and file
scope where relevant. Surface it once at batch start so every planned write —
the closes included — is visible before any executes.

Then execute the **close-candidates**: post the research comment citing the fixing
code/PR and `gh issue close` each (autonomous — report each close). Set each row's
`Status: closed` and append the close to the manifest Outcomes log **before**
removing it from the active queue, so a resume after step 4 still reports these
closes in the final table. Proceed to fixes (step 5) and merges (step 6).

## 5. Execute Fixes — Reuse `$work-issue` in Subagents, Hand-Off Mode

When an issue goes **in-flight**, flip its manifest status to `in-flight`, then
capture its branch by **reading back the name the dispatched `$work-issue`
actually created** — from the run's completion report (which names its branch/PR
ref) or `gh pr view <PR> --json headRefName` once the PR exists — and record
*that* in the `Branch` column. Do not pre-assign a name and assume it holds:
`$work-issue` derives its own `feat/<short-slug>-<n>` and accepts no branch input,
so a guessed name would diverge from the real branch. A subagent returns only its
final report, so it cannot stream the branch mid-run — meaning between dispatch and
that report **no branch is recorded**, a known residual: a mid-wave orchestrator
crash then relies solely on the naming-scheme fallback. That fallback: step-3
reconcile recovers the branches by matching the full `feat/<short-slug>-<n>` shape
ending in `-<n>` in `git branch` (the full shape, not any `*-<n>`, so issue `#1`
matches neither `...-11` nor an unrelated `feat/other-1`) — contingent on
`$work-issue`'s current naming scheme.

**Every fix is a subagent that runs `$work-issue <n>` to a green + mergeable PR
and then stops** — it does **not** run its own step 8 `$merge-cleanup` and is
**never** handed merge authorization; the orchestrator merges (step 6). Because a
dispatched run never reaches the merge-authorization check, there is no inline "am
I the orchestrator or the dispatched run?" ambiguity. Each subagent prompt is
self-contained (fields listed below) and **must end with the subagent report
contract** (`AGENTS.md`) — a ~1–2k-token summary (outcome, branch/PR ref, files
touched, guardrail status, blockers) and nothing else, no diffs/logs/file bodies or
lifecycle transcript. That report, not the transcript, is what bounds the
orchestrator's per-issue context. Each prompt carries:

- issue number and acceptance criteria,
- the **assigned ADR/migration numbers** and **file scope** from the manifest,
- the guardrail commands, `BASE_BRANCH`, and the ADR-index coupling verdict from
  step 2 — the last so an ADR-producing run knows whether to carry its own index
  row without rediscovering the gate,
- the model tier from triage,
- (parallel only) the external worktree path (`../<repo>-worktrees/<branch>` —
  outside the repo tree, per `$work-issue`'s worktree-placement rule).

**Wave size 1 (serial).** Dispatch one subagent, wait for its green + mergeable
PR, merge it (step 6), then dispatch the next. A step-3 reconcile continuation (an
existing incomplete branch) is also a subagent dispatch — see step 3 for whether it
restarts clean (the default) or reuses the branch.

**Waves of up to 5 (parallel).** Dispatch **worktree-isolated** subagents via the
Codex multi-agent tooling, up to **5 per wave** (matching `$merge-dependabot`'s waves of 5), all
subagent dispatches in a **single message** per wave; subsequent waves start after the
current wave completes.

## 6. Merge Serially — Orchestrator Only

As each issue reaches a green + mergeable PR, run `$merge-cleanup` on the
operator-authorized branch (this skill is the operator authorization). Merge one
PR, then for **each remaining in-flight PR** re-check `mergeStateStatus`; if it went
`BEHIND`/`DIRTY`, rebase it onto the updated `BASE_BRANCH`, regenerate generated
artifacts, rerun the guardrails, and re-confirm green + mergeable before merging it.
Never merge an unmergeable PR on the strength of previously-green checks.

In parallel mode the subagent that built the PR has finished and its worktree may
be gone, so the **orchestrator** owns this recovery: check the branch out in a
fresh external worktree (`git worktree add ../<repo>-worktrees/<branch>`) and use
the ADR/migration numbers and file scope you assigned that issue in step 4 to
regenerate artifacts correctly, or re-dispatch the original subagent with that same
context. Retain the step-4 assignments until every PR in the batch is merged — they
are the inputs this recovery depends on.

If the repo keeps a hand-maintained ADR index, its rows are **yours**: subagents were
told to write only their ADR file and report `index row pending`. Append every pending
row for the wave **once**, after the wave's last PR merges, on its own branch — never
mid-wave, which recreates the conflict the split exists to avoid.

That split inverts where CI gates the index (ADR 0019). A required check enforcing one
index row per ADR file holds every ADR-bearing PR red until its row lands, and the merge
it blocks is the one that would trigger your append — a deadlock, not a sequencing
wrinkle. There each subagent adds its own row in its own PR, and you own only the
collisions: expect adjacent-insertion conflicts between sibling PRs and resolve them
in the serial-merge rebase above, which is already where this class of overlap is
reconciled. `$preflight` step 4 reports the coupling, so you know which wave this is
before you dispatch it, and expect no `index row pending` reports from that wave.

**Resolve collisions; do not author rows there.** Such a guard checks both directions
and usually compares the `Status` keyword between a record and its row, so a row you
add ahead of its ADR file fails it on `main` — a row with no record, or a status that
leads the record's. You cannot pre-add rows at dispatch to spare the subagents the
conflict; the only safe row is one that merges in the same PR as its record.

The PR's `Closes #<n>` trailer should close the issue — but that auto-close only
fires on a merge into the repo's **default** branch, so **verify** it with
`gh issue view <n> --json state` after merging. If the issue is still open, close
it explicitly (authorized) and note why, so the final report reflects real state
rather than an assumption. Record the outcome (`merged PR#<n>` / `closed`) in the
manifest — status column and outcomes log — before moving to the next PR, so an
interrupted merge phase resumes knowing which issues are already done. Clean up
the branch and any external worktree. Do not propagate merge authorization to
subagents.

## 7. Re-Enqueue Newly Filed Issues

If triage or fixing surfaced a new issue (filed with `gh issue create` and linked
to an in-scope issue), add a row to the manifest queue (and its the task plan mirror)
and loop back to step 3 for it. Only enqueue issues **traceable to this batch's
investigation** — never open-ended repo-wide discovery. Report each enqueue so
scope creep stays visible.

## 8. Done

Your turn ends only when the queue is empty — every original and newly-filed
in-scope issue is closed, merged, or **blocked**.

An **issue-local blocker** (one issue's fix cannot pass guardrails, a design
question only the user can answer) does not halt the batch. Drain the work that is
already ready — merge the mergeable PRs, execute the confirmed closes — then mark
that one issue **blocked** with the reason and continue the rest of the queue.
Reserve a full-batch halt for a **global** blocker (dirty tree, missing auth).

**The manifest row is not the parked state — GitHub is** (github-tracking skill). Who
writes the label follows the skill's one-writer-per-edge rule, so it splits on whether a
dispatched `$work-issue` **parked the issue itself**:

- **Its report names a blocker** — then it already posted the `WORK:TRAJECTORY` note and
  set `status:blocked`/`status:needs-human` (see `$work-issue`, *On a Blocker*). Record
  its `Status: blocked` row and the reason from that report; do **not** re-write the
  label.
- **Anything else you block** — a triage that came back inconclusive, a merge-phase
  blocker on a PR whose subagent already finished and is gone, an orchestrator-level
  decision. No dispatched run parked it, so the edge is yours: post the
  `WORK:TRAJECTORY` note (parked phase, branch/PR if any, what a human must supply), then
  ensure-create and set the label — `status:blocked` for an external dependency,
  `status:needs-human` where a human must diagnose.

Either way the manifest row and the GitHub state must agree before you move on: the
manifest resumes *this* run, the label is what `$recover-orphans` and a human read after
it.

When the queue is empty, **flip the manifest header to `Status: complete`** so a
later run of the same selector starts a fresh campaign instead of silently
reattaching to this finished one (step 1's `complete` routing). A batch left
`blocked` stays `active` — it is not done.

Report a final table: issue → outcome (**closed-already-fixed** / **merged-PR#** /
**blocked: reason**) → notes.
