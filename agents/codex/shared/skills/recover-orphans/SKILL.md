---
name: recover-orphans
description: >-
  Reconcile GitHub status labels with actual pull-request and branch state,
  reset stale orphaned work, and remove residual labels from closed issues.
  Use between work or campaign runs when issue workflow state may be stale.
---
# Recover Orphaned Issues

Reconcile the `status:` labels (see the `github-tracking` skill) against actual GitHub
state. Run this **between** pipeline runs — not while a `$campaign` or `$work-issue` is
actively working the same repo. Read → plan → one confirmation → apply.

## Steps

1. **Resolve repo.** `gh repo view --json nameWithOwner --jq .nameWithOwner` → `owner/name`.
2. **Sweep in-flight issues.** Do **not** filter with `gh issue list --label status:...` —
   `gh` mis-encodes the colon and multiple `--label` flags AND (see the skill's colon-label
   gotcha), so either returns nothing. List by state once and filter **client-side**:
   `gh issue list --repo <owner/name> --state open --json number,labels,title --limit 500`,
   then keep issues carrying any in-flight `status:` value (`in-progress`, `in-review`,
   `awaiting-merge`). For each, check reality:
   - **merged PR with `Closes #N`** (`gh pr list --repo <owner/name> --state merged --search
     "N in:body"` — verify the `Closes` link) → plan: close issue, strip `status:` labels.
   - **open PR** → plan: correct the label to match the PR's actual state.
   - **no PR, no matching branch, and stale** (gate below) → plan: reset to `status:ready`.
3. **Staleness gate** (prevents clobbering a legitimately-quiet in-flight issue whose branch
   was never pushed). Reset a `status:in-progress` issue only when ALL hold:
   (a) no open/merged PR references it;
   (b) no branch matches its name/number (`git branch -a`, `git ls-remote --heads`);
   (c) no `WORK:SCOPE` annotation posted after the current `status:in-progress` label was
       applied (liveness — read via the skill's latest-complete recipe);
   (d) the `status:` label's age exceeds the threshold (default 60 min), read via the
       skill's timeline recipe. **Empty timeline result = stale-unknown → do NOT reset;
       surface for a human.** Fail closed, never clobber.
4. **Surface, don't reset, `blocked`/`needs-human`.** List them in the plan table as *held*
   with their parked-phase note (from `WORK:TRAJECTORY`; for a birth-blocked issue with no
   trajectory note, the `Blocked by #<n>` body line is the parked-state record); a human
   owns their exit edge. Only clean up if a merged PR already closed the underlying work.
5. **Strip stale labels from closed issues.** Same colon-label caveat — list and filter
   client-side: `gh issue list --repo <owner/name> --state closed --json number,labels
   --limit 500`, keep those still carrying any `status:` value → plan: remove the residual
   `status:` label (closed-state is authoritative).
6. **Plan → confirm → apply.** Present the full reconciliation table (`#issue → action`).
   List any branch before touching it. After one explicit confirmation, apply per issue;
   a per-issue failure does not abort the sweep.

## Hard constraints

- Between-runs reconciler; do not run concurrently with active `$work-issue`/`$campaign`.
- Explicit `--json` fields on every `gh` read.
- Fail closed on stale-unknown; never auto-move `blocked`/`needs-human`.
- One confirmation before any write; list branches before acting on them.
