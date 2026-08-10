---
name: campaign
description: "Orchestrate a set of GitHub issues until each is closed as already fixed or resolved by a merged pull request, including triage, dependency planning, per-issue execution, serial merging, and newly discovered work. Use when asked to run a campaign, clear an issue set, or drive a batch of issues to done."
---

Drive a batch of GitHub issues to completion — each issue either closed (already fixed) or merged (fixed by a PR).

**Single continuous task.** This is one task from start to final merge. Checkpoints (triage done, CI green, PR merged) are not turn boundaries. End only when the queue is empty or you hit a **global** blocker (dirty tree, missing auth). Issue-local blockers don't stop the batch — mark them blocked and continue.

**Authorization.** Invoking `$campaign` authorizes you to auto-close issues shown as already-fixed and self-merge green + mergeable PRs. This authorization stays with you — never propagate merge rights to subagents. Each `$work-issue` stops at a green + mergeable PR; you handle the merge.

## 1. Resolve the Issue Set

Parse the user's selector into issue numbers. Support:
- Explicit numbers: `992 994 1001`
- Ranges: `992-997` (inclusive; skip non-existent)
- Natural language: `open issues labeled bug` — paginate manually, never `--paginate` (unbounded). Pass the search string and cursor as GraphQL variables — never interpolate into the query literal, since qualifiers like `label:"good first issue"` carry quotes that break the string: `gh api graphql -f q='repo:<owner>/<repo> is:open is:issue <terms>' -f query='query($q: String!, $endCursor: String) { search(query: $q, type: ISSUE, first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { ... on Issue { number labels(first: 100) { nodes { name } } } } } }'`. Loop while `hasNextPage`, re-running with `-f endCursor=<cursor>` (omit it on the first page), max 5 pages. Then probe once with `first:1` and the fifth cursor — a returned node means >500 matches: fail with "selector too broad; use explicit numbers or narrow the query". The `repo:` qualifier scopes results, so per-node repo validation is unnecessary

Drop `epic`-labeled issues from the set (report the drop). NL selectors get labels from the GraphQL result; for explicit/range paths, fetch labels to check this. Apply the same filter to new matches during resume reconciliation — never enqueue an epic.

Any trailing text after the selector is **completion notes** — context on what "done" means. Carry these through as **private dispatch context**: they flow verbatim into subagent prompts only, never onto public GitHub surfaces. When notes are present, derive a **public-safe summary** once, here (strip private context, host paths, credentials), and record it in the manifest as `Public-safe notes`. Acceptance criteria, `WORK:` annotations, comments, and PR bodies use only the summary. If you cannot derive a confident public-safe summary, stop and ask the user to supply one before proceeding.

**Resolve `campaign_root` before any writes.** It's the main repo root (not current directory, which might be a worktree):

```bash
campaign_root=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
```

Use `"$campaign_root/..."` for all reads/writes — a bare `.agent/campaigns/...` from a worktree creates a forked manifest.

**Initialize the manifest** (find-or-create, never blind-create). Key it on a **selector identity stable across runs**:
- For explicit numbers/ranges: sorted deduped requested numbers (before the "skip non-existent" filter)
- For NL selectors: lowercased, whitespace-collapsed query string
- For mixed selectors: sorted numbers + normalized query (deterministic order)

Slug is a short hash of this normal form. Store the full normal form in the manifest as `Normalized-selector`. Use `"$campaign_root/.agent/campaigns/<slug>.md"`.

**Hash collision handling:** On any file match, confirm loaded `Normalized-selector` equals this run's. On mismatch, use `<slug>-2.md`, etc.

**Keep manifest out of git** without relying on target repo's `.gitignore`** (required before any manifest write or resume mutation**):

```bash
# Check if ignore file is tracked
git -C "$campaign_root" ls-files --error-unmatch .agent/.gitignore  # exit 0=tracked, 1=untracked, other=error
```

- Exit 0 (tracked): leave alone, but verify it ignores `.agent/campaigns/`
- Exit 1 (untracked): create dir, write `*` to `.agent/.gitignore` via temp file in `$campaign_root/.agent/` then rename, with EXIT trap to clean temp on interruption; clear trap only after rename succeeds
- Other: stop with named blocker

Verify: `git -C "$campaign_root" check-ignore -q .agent/campaigns/`. Stop if fails.

**Routing:**
- **No file** → create with `Status: active`
- **File with `Status: active`** → **resume**: load it, skip init, don't overwrite non-`pending` rows. Manifests written before the `Public-safe notes` field existed lack it — backfill before validation: derive the summary from the stored `Completion notes` (`none` when notes are `none`; ask the user when safe derivation is impossible) and write the manifest back atomically. For NL selectors, reconcile live resolved set against loaded queue — enqueue new matches. If completion notes differ, surface and confirm; on confirmed change, re-derive the public-safe summary and update the manifest.
- **File with `Status: complete`** → archive as `<slug>-done-<timestamp>.md`, create fresh

**You are the only writer.** Subagents reference manifest facts by value (copied into prompts), never write it. Write atomically (temp + rename).

**Edits are surgical, never `replace_all`.** A `replace_all` edit keyed on a too-short match string rewrites every row containing it, silently flipping rows outside the current edit. Match on the full unique row (issue number + status), not a substring. Re-read the manifest after each edit to confirm only the intended row changed; if not, stop with a named blocker before any further write or GitHub action.

**Validate manifest before use:** required fields present, issue rows unique, states recognized (`pending|triaged|in-flight|ready-to-merge|merged|closed|blocked`), table structure valid. Stop with blocker on failure.

Manifest schema:

```markdown
# Campaign: <slug>  (started <YYYY-MM-DD>)
- Status: active            # flip to `complete` at end
- Selector: <raw selector>
- Normalized-selector: <normal form>
- Completion notes: <text or "none">
- Public-safe notes: <derived summary or "none">
- Completion condition: every queued issue closed or merged
- BASE_BRANCH: <filled by step 2>
- Guardrail commands: <filled by step 2>
- ADR-index coupling: <filled by step 2>

## Queue
| Issue | Status | Branch | Verdict | ADR/migration # | File scope | Wave | PR | Outcome |
|-------|--------|--------|---------|-----------------|------------|------|----|---------|
| #NNN  | pending| —      | —       | —               | —          | —    | —  | —       |

## Outcomes log
<appended per close/merge/block>
```

Status progression: `pending → triaged → in-flight → merged | closed | blocked`

## 2. Environment Discovery

Run `$preflight` **once** for the batch to get `BASE_BRANCH`, guardrail commands, gh auth, and ADR-index coupling (`coupled` | `not coupled` | `no index`). Record these in the manifest. On resume, read from manifest and skip re-running (re-confirm auth and clean tree only). Stop on blockers before touching issues.

## 3. Triage

**Reconcile state first.** Read the manifest before anything else.

For each queued issue, check for artifacts from prior runs:
- **Already closed** → done; drop without re-closing
- **`status:` label set** → map to campaign state: `ready`/`needs-triage` → `pending` (triage); `in-progress`/`in-review` → `in-flight` (reconcile artifacts); `awaiting-merge` → verify PR then `ready-to-merge`; `blocked`/`needs-human` → `blocked`. Treat closed as authoritative regardless of label.
- **Existing PR green + mergeable** → mark `ready-to-merge`, carry to step 4
- **Persisted step-4 assignments exist** → read them back, don't re-derive
- **Existing branch/PR incomplete** → **recover branch first**: if a PR exists, resolve its number from the issue link, then `gh pr view <PR> --json headRefName`; else match `feat/<short-slug>-<issue-number>` in `git branch` or `git ls-remote --heads origin` (full shape, not `*-<n>` suffix — #1 must not match ...-11). Persist to manifest. **PR-linked branch → reuse by default** (the PR explicitly names it, satisfying `$work-issue`'s reuse rule). **Convention-only branch → ask the user** reuse-or-restart before dispatch, and carry the operator's decision in the prompt. Deleting any branch requires explicit user confirmation
- **No artifacts** → triage normally

**Dispatch read-only triage subagents** (up to 5 parallel). Each prompt carries completion notes verbatim (private dispatch context — safe inside prompts). Subagent investigates issue body, linked PRs/commits, and current code. Return only:

- **verdict**: `close-candidate` | `fix` (subtype: `trivial-bugfix` | `governed-small-change` | `non-trivial`)
- **evidence**: citations (`file:line`, commit SHA, PR number)
- **rationale**: ≤300 tokens explaining why

For `governed-small-change`, also return: decision reference, kind, accepted status, governed behavior, testable acceptance criteria. These are evidence, not authority — `$work-issue` revalidates.

Pick model by signals: clearly mechanical → fast model; ambiguous/wide-surface → capable model.

**Verdict handling:**
- `close-candidate` → confirm with `bug-claim-verifier` or `$challenge` before closing. **Confirmed** → keep `close-candidate`; don't close here — batch closes in step 4 after plan is visible. **Rejected or inconclusive** → the already-fixed claim is unproven, so the issue needs work: re-verdict as `fix` (subtype from the verifier's evidence; default `non-trivial` when unclear), or `blocked` with reason if even that can't be determined. Persist the transition in the manifest before presenting the plan.
- `fix` → subtype drives model selection in step 4. Cheap-model `trivial-bugfix`/`governed-small-change` is a floor; escalate if fix proves subtler.

Record verdicts in manifest `Verdict` column. Reconcile states (`ready-to-merge`, already-closed) live in `Status`.

## 4. Plan the Fix Batch

Count issues needing fixes. **Every fix runs in a subagent** — never inline.

**Wave size:**
- **Serial (size 1)**: for coupled issues (overlapping file scopes, ordering dependencies). Merge each before next.
- **Parallel (up to 5)**: for independent issues (disjoint scopes, no dependencies).

Record wave in manifest (`Wave` column): `s1`, `s2`... for serial (order = merge order), `w1`, `w2`... for parallel.

**Pre-assign ADR/migration numbers and file scope** even for serial — crashed issues need consistent numbers on re-dispatch. Persist these in manifest. File scope is a hint, not guarantee.

Present triage/plan table: issue → verdict, wave, assigned numbers, file scope.

Execute **close-candidates** (all remaining ones are confirmed — rejected/inconclusive candidates were re-routed in step 3): post research comment citing fixing code/PR, `gh issue close` each. Set `Status: closed`, append to outcomes log before removing from queue.

## 5. Execute Fixes

When issue goes **in-flight**, flip status and **read back the actual branch name** from subagent report or `gh pr view --json headRefName`. Record in `Branch` column. Don't pre-assign — `$work-issue` derives its own `feat/<short-slug>-<n>`.

**Every fix is a subagent running `$work-issue <n>` to green + mergeable PR, then stopping.** Subagent must reflect the **public-safe summary** of the completion notes — never the verbatim notes — in acceptance criteria and PR body. No merge authorization to subagents. Subagent report (per `AGENTS.md`): ~1-2k token summary with outcome, branch/PR ref, files touched, guardrail status, blockers. No diffs/logs/file bodies.

Each prompt carries:
- Issue number, acceptance criteria, **completion notes verbatim** (private dispatch context) and the **public-safe summary** (the only form allowed on public surfaces: acceptance criteria, `WORK:` annotations, PR bodies)
- **For resumed work:** recovered branch name and `reuse` decision
- For `governed-small-change`: subtype, decision reference, kind, accepted status, governed behavior, criteria
- Assigned ADR/migration numbers, file scope
- Guardrail commands, `BASE_BRANCH`, ADR-index coupling verdict
- Model tier from triage
- (Parallel only) external worktree path (`../<repo>-worktrees/<branch>`)

**Serial:** dispatch one, wait for green + mergeable PR, merge (step 6), repeat.

**Parallel:** dispatch up to 5 worktree-isolated subagents in single message per wave.

## 6. Merge

**Verify each issue's PR before merging it.** Green + mergeable says CI passed and Git can fast-forward — neither says the PR contains the work you dispatched. (The orchestrator's own ADR-index PR below carries no issue and no manifest row, so none of this applies to it.)

- **The PR must close its assigned issue** — `gh pr view <PR> --json closingIssuesReferences`. A reference to any *other* issue takes the hold below: merging closes a row the campaign may still have queued, and a later resume reads that close as already-fixed. A missing reference is recorded and left to the post-merge auto-close check below, which closes the issue explicitly.
- **Compare `gh pr diff <PR> --name-only` against that issue's `File scope` cell from step 4.** A changed path is in scope when it equals a repo-relative path named in the cell, sits under a directory named there, or sits under the directory holding a glob entry. Don't take the list from `gh pr view --json files`: that field returns the first 100 paths with no truncation marker. When the cell is still `—` or holds nothing parseable as a path, the comparison **did not run** — record that and merge on the read below rather than treating an absent hint as a mismatch, since rows reconciled in step 3 and rows from a manifest predating the assignment carry no scope, and parking those parks correct work. A cell that *does* carry scope is different: if the diff command exits nonzero after one retry, hold rather than merge. The PR is green and will still be there; the merge is the irreversible half.
- **A diff that succeeds and lists no files blocks.** Nothing was changed, so nothing can be carrying the fix. A nonzero exit is the previous bullet's case, not this one.
- **Changed files outside the scope do not block by themselves.** Step 4 assigns scope as a hint, and a correct fix routinely touches a file the plan didn't predict; a check that hard-blocks on any deviation fires on legitimate work and gets routed around. A file is accounted for when the PR body, a commit message, or the subagent's report ties it to **the assigned issue**; when it is the ADR index under `coupled` coupling below, or a file your own branch refresh or artifact regeneration touched, both of which this step mandates and neither of which names an issue; or when the operator already accepted it, per the hold below. Everything else is **unrelated** — hold that one merge for the operator's decision. A file tied to a *different* tracked issue is the case most needing that decision, not an exemption from it: merging it lands a sibling's work early and can auto-close a row still queued. A nonempty diff overlapping nothing in the scope is held the same way — a probably-stale hint, not proof the PR is wrong. Never split, revert, or cherry-pick inside the PR; that surgery is undefined here and risks discarding work.

Whether the PR *implements* its issue stays yours to judge. The closing reference says which issue it claims and the comparison says where it landed; neither says the work is there. Read the PR body, its stated acceptance criteria, and the `WORK:REVIEW` summary, and if that leaves you unable to say the changes are present, hold rather than merge on the file comparison alone.

**A hold does not clear itself.** Post `WORK:TRAJECTORY`, set `status:needs-human`, record the row as blocked, and keep draining the rest of the queue. The PR stays green and mergeable throughout — nothing about it will change — so only an operator's decision lifts the hold, and step 3's `green + mergeable → ready-to-merge` reconciliation does not apply to a row carrying one. Put the same facts in that issue's outcomes-log entry: whether the comparison ran, which out-of-scope paths it found, and how each was accounted for. That entry is also how the decision comes back: an operator lifts the hold by recording the paths they accept there, and a path recorded as accepted is accounted for on every later pass. Without it the next run re-derives the same finding and re-holds forever, and a resume would otherwise be re-deriving all of this from a subagent report that is gone.

As each issue reaches green + mergeable, run `$merge-cleanup` (you are authorized). Merge one PR, then for each remaining in-flight PR re-check `mergeStateStatus`. If `BEHIND`/`DIRTY`, merge `BASE_BRANCH` into PR branch, regenerate artifacts, rerun guardrails, re-confirm green. If the repo forbids merge commits (linear history) and rebasing a pushed branch is denied, stop with a named blocker.

In parallel mode, subagent is done and worktree may be gone. You own recovery: check out branch in fresh external worktree or re-dispatch subagent with same context. Use step-4 assignments for artifact regeneration.

**ADR index handling** (three states: `coupled` | `not coupled` | `no index`):
- **`no index`**: skip row handling entirely
- **`not coupled`** (index exists, not CI-gated): subagents write only ADR file, report `index row pending`. You append all pending rows **once** after wave's last PR merges, on its own branch.
- **`coupled`** (index is CI-gated): subagents add their own rows in their PRs. You resolve adjacent-insertion conflicts during the serial-merge branch refresh. Expect no `index row pending` reports.

Verify auto-close: `gh issue view <n> --json state` after merge. If still open, close explicitly and note why. Record outcome in manifest before moving to next PR. Clean up branch and worktree.

## 7. Re-Enqueue New Issues

If triage/fixing surfaced new issues (filed with `gh issue create` and linked), add to manifest queue and loop to step 3. Only enqueue issues **traceable to this batch**. Report each enqueue.

## 8. Done

**Drained** means every row is `closed`, `merged`, or `blocked`. End your turn when drained, leaving manifest `active` if any `blocked` rows remain.

**On resume with blocked rows:** revalidate each blocker against its `WORK:TRAJECTORY` note and current state. If resolved, transition to appropriate state (`pending`, `in-flight`, etc.) and continue; if not resolved, leave blocked.

**Issue-local blockers** don't halt the batch. Drain ready work, mark blocked with reason, continue.

**GitHub is the parked state** (github-tracking skill). Who writes the label depends on who parked it:
- **Subagent reported blocker** → it already posted `WORK:TRAJECTORY` and set `status:blocked`/`status:needs-human`. Record `Status: blocked` with reason from report. Don't rewrite label.
- **You block it** (triage inconclusive, merge-phase blocker, orchestrator decision) → post `WORK:TRAJECTORY` note, ensure-create and set label (`status:blocked` for external dependency, `status:needs-human` for human diagnosis).

Ensure manifest row and GitHub state agree before moving on.

Flip manifest to `Status: complete` only when every row is `closed` or `merged`. Campaigns containing `blocked` rows stay `active`.

Report final table: issue → outcome (`closed-already-fixed` / `merged-PR#` / `blocked: reason`) → notes.
