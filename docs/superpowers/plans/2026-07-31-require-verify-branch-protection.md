# Require Verify Branch Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development
> (recommended) or executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require GitHub Actions check `verify` for `main`, prove a failed run is
blocked, document recovery, and resolve debt record 0001.

**Architecture:** GitHub classic branch protection owns the external merge gate and
binds `verify` to GitHub Actions app ID `15368`. A temporary invalid debt record drives
the real workflow red; GitHub's failed check and `BLOCKED` merge state prove enforcement
without attempting a merge. The repository records the resulting policy and recovery
procedure in README and resolves the existing debt marker in place.

**Tech Stack:** GitHub REST API through `gh`, GitHub Actions, Markdown decision records,
shell assertions with `jq`, and repository guardrail `just verify`.

## Global Constraints

- Base branch is `main`; work only from external worktrees.
- The exact required context is lowercase `verify`, observed on PR #19.
- The producer is GitHub Actions app ID `15368`, observed on PR #19's check run.
- Require no unrelated review, signature, history, deletion, or conversation policy.
- Never issue a merge command for the deliberately failing proof PR.
- Before rollback, restore only if live policy exactly matches this run's expected write.
- Keep tokens, private paths, host data, and runtime artifacts out of the repository.
- Run `just verify` before every persistent feature-branch commit and before shipping.
- The operator-authorized failing proof has one bounded exception: its exact temporary
  fixture commit uses `--no-verify` because the proof must fail the same gate the hook runs.
  Never reuse that exception on the feature branch or any other file.

---

### Task 1: Configure and prove the required check

**Files:**

- Temporarily create and remove: `docs/debt/9999-branch-protection-proof.md` on the
  proof branch only
- No persistent repository file changes

**Interfaces:**

- Consumes: PR #19 check-run metadata and the empty pre-write branch-policy baseline
- Produces: protected `main`, a closed proof PR, and evidence values for Task 2

- [ ] **Step 1: Reconfirm the check producer and empty policy immediately before write**

Run:

```bash
repo_name=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
head_sha=$(gh pr view 19 --json headRefOid --jq .headRefOid)
gh api "repos/$repo_name/commits/$head_sha/check-runs" \
  --jq '.check_runs[] | select(.name == "verify") |
    {name, app_id: .app.id, app_slug: .app.slug, conclusion}'
gh api "repos/$repo_name/rulesets" --jq 'length == 0'
gh api "repos/$repo_name/rules/branches/main" --jq 'length == 0'
```

Expected: one successful `verify` from app ID `15368` / slug `github-actions`, and
both rules queries return `true`. `GET branches/main/protection` must still return
HTTP 404; any live policy or identity drift stops the write for reconciliation.

- [ ] **Step 2: Apply the minimal protection policy**

Run this exact request only after Step 1 remains empty:

```bash
gh api --method PUT "repos/$repo_name/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": false,
    "contexts": [],
    "checks": [{"context": "verify", "app_id": 15368}]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
```

Expected: HTTP success with protection for `main`.

- [ ] **Step 3: Assert the exact post-write state**

Run:

```bash
policy=$(gh api "repos/$repo_name/branches/main/protection")
policy_matches() {
  jq -e '
  .required_status_checks.strict == false and
  .required_status_checks.contexts == ["verify"] and
  .required_status_checks.checks == [{"context":"verify","app_id":15368}] and
  .enforce_admins.enabled == true and
  .required_pull_request_reviews == null and
  .restrictions == null and
  (.required_linear_history.enabled // false) == false and
  (.allow_force_pushes.enabled // false) == false and
  (.allow_deletions.enabled // false) == false and
  (.block_creations.enabled // false) == false and
  (.required_conversation_resolution.enabled // false) == false and
  (.lock_branch.enabled // false) == false and
  (.allow_fork_syncing.enabled // false) == false
  ' <<<"$1"
}
policy_matches "$policy"
```

Expected: `true` with exit 0. Reuse `policy_matches` for every later rollback decision;
it normalizes omitted disabled fields from the GET representation while asserting every
field written in Step 2. On mismatch, re-read policy and delete protection only when it
passes `policy_matches`; otherwise preserve concurrent changes and stop for manual
reconciliation.

- [ ] **Step 4: Create the temporary failing proof PR**

Derive an external sibling worktree path without recording a host-specific path:

```bash
primary_worktree=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
proof_worktree="$(dirname "$primary_worktree")/agent-config-worktrees/proof-verify-required-16"
```

Create `proof_worktree` on branch `proof/verify-required-16` from current
`origin/main`. Add the following invalid file with `apply_patch`, commit it, push it,
and open a PR titled `test: prove verify blocks merge`:

```markdown
# Branch protection proof

This deliberately malformed debt record must fail the decision-record gate.
```

The normal pre-commit hook runs `just verify`, so the exact proof commit must bypass
that hook once:

```bash
git -C "$proof_worktree" add docs/debt/9999-branch-protection-proof.md
git -C "$proof_worktree" commit --no-verify \
  -m "test: make verify fail for protection proof"
```

This exception is authorized only for branch `proof/verify-required-16` and that one
fixture path. Immediately push it and use the CI observation in Step 5 to prove the
intended record-gate failure. Every persistent commit remains green and hook-verified.

The PR body states that it is a temporary, known-failing enforcement proof for #16
and must not be merged.

- [ ] **Step 5: Observe the red check and blocked merge state**

After CI completes, run:

```bash
gh pr checks "$proof_pr" --json name,state,link,bucket,workflow
gh pr view "$proof_pr" --json number,headRefOid,mergeable,mergeStateStatus,state,url
proof_sha=$(gh pr view "$proof_pr" --json headRefOid --jq .headRefOid)
gh api "repos/$repo_name/commits/$proof_sha/check-runs" \
  --jq '.check_runs[] | select(.name == "verify") |
    {name, app_id: .app.id, conclusion, details_url, head_sha}'
```

Expected: `verify` from app ID `15368` is `FAILURE`; `mergeable` is `MERGEABLE`;
`mergeStateStatus` is `BLOCKED`. Inspect the failed job and confirm the malformed
record caused the failure. Do not run any merge command. Capture one outcome value:

- `proved` only when all four observations and the expected failure cause match;
- `inconclusive` for wrong check identity, producer, result, failure cause, conflicts,
  missing CI, or a timed-out dependency; or
- `not-blocked` when the conflict-free failed-check PR does not report `BLOCKED`.

Every outcome proceeds through Step 6 cleanup. Leave debt 0001 open unless the outcome
is `proved`. For `not-blocked`, run the compare-before-rollback branch in Step 6 after
cleanup. An `inconclusive` result leaves the exact read-back-verified policy in place for
diagnosis but makes no enforcement claim.

- [ ] **Step 6: Record evidence and clean every proof artifact**

Always clean the temporary artifacts before posting evidence. If a partial failure
occurred before PR creation, skip only the absent PR operation; still remove every
branch or worktree that exists. For a created proof PR, close it. Then delete the exact
remote branch, remove its external worktree, and delete its exact local branch:

```bash
if [[ -n ${proof_pr:-} ]]; then
  gh pr close "$proof_pr"
fi
if git ls-remote --exit-code --heads origin refs/heads/proof/verify-required-16; then
  git push origin --delete proof/verify-required-16
fi
if git worktree list --porcelain | rg -F "worktree $proof_worktree"; then
  proof_status=$(git -C "$proof_worktree" status --short --untracked-files=all)
  if [[ -n "$proof_status" ]]; then
    unexpected=$(printf '%s\n' "$proof_status" |
      rg -v '^(A |\?\?) docs/debt/9999-branch-protection-proof\.md$')
    if [[ -n "$unexpected" ]]; then
      print -u2 -- "refusing proof cleanup with unexpected changes: $unexpected"
      exit 1
    fi
    if git -C "$proof_worktree" ls-files --error-unmatch \
      docs/debt/9999-branch-protection-proof.md; then
      git -C "$proof_worktree" restore --staged -- \
        docs/debt/9999-branch-protection-proof.md
    fi
    if [[ -e "$proof_worktree/docs/debt/9999-branch-protection-proof.md" ]]; then
      trash "$proof_worktree/docs/debt/9999-branch-protection-proof.md"
    fi
  fi
  git worktree remove "$proof_worktree"
fi
if git show-ref --verify --quiet refs/heads/proof/verify-required-16; then
  git branch -D proof/verify-required-16
fi
```

Verify cleanup after those operations:

```bash
if [[ -n ${proof_pr:-} ]]; then
  gh pr view "$proof_pr" --json state,headRefName,url
else
  print -- 'proof PR cleanup: not-created'
fi
git ls-remote --exit-code --heads origin refs/heads/proof/verify-required-16
git branch --list proof/verify-required-16
git worktree list --porcelain
```

Expected: PR state `CLOSED`, or explicit `not-created`; `ls-remote` exits 2 because the
ref is absent; local branch output is empty; worktree list omits the proof path. Treat
the expected `ls-remote` exit 2 as the absence assertion rather than a suite failure.

If the outcome is `not-blocked`, re-read live protection. Delete it only if
`policy_matches` succeeds, because the captured baseline was empty; confirm the GET then
returns HTTP 404. If `policy_matches` fails, preserve live policy and report both
snapshots for manual reconciliation.

Only after cleanup and any conditional rollback are verified, post issue #16 evidence
containing the policy outcome, proof outcome (`proved`, `inconclusive`, or
`not-blocked`), proof PR number and URL when created, proof head SHA, check URL and
producer when emitted, merge-state observation, cleanup results, and rollback result.
Stop unless the outcome is `proved` and the expected policy remains live.

### Task 2: Document recovery and resolve the debt

**Files:**

- Modify: `README.md`
- Modify: `docs/debt/0001-require-verify-branch-protection.md`

**Interfaces:**

- Consumes: Task 1's verified policy and proof evidence
- Produces: maintainer recovery instructions and an immutable debt resolution marker

- [ ] **Step 1: Run the record gate before changing the resolution marker**

Run:

```bash
just records
```

Expected: debt 0001 is valid and still open. This is the pre-change baseline; do not
resolve it before Task 1 satisfies its condition.

- [ ] **Step 2: Add branch-protection recovery to README**

Under Verification, document:

- `verify` is required for `main` and bound to GitHub Actions app ID `15368`;
- how to list names from a real PR with `gh pr checks`;
- how to get the producer app ID from that PR's head check runs;
- how to inspect `branches/main/protection/required_status_checks`; and
- how to PATCH only the required-status-check endpoint with the newly observed context
  and app ID when a rename or stale context leaves the check stuck.

The recovery must say to wait for a real successful replacement run before updating,
preserve `strict: false`, and never clear all required checks as a workaround.

- [ ] **Step 3: Resolve debt record 0001 in place**

In `docs/debt/0001-require-verify-branch-protection.md`, remove
`review-by: 2026-08-31` and replace `Open` with:

```markdown
> **Resolved by issue #16 enforcement proof** (2026-07-31)
```

Change no substantive section outside `## Status`.

- [ ] **Step 4: Verify the documentation and resolution**

Run:

```bash
git diff --check
just verify
```

Expected: 140 record regression cases pass, root records are valid, all repository
linters/tests pass, actionlint passes, and zizmor reports no findings.

- [ ] **Step 5: Commit the persistent implementation**

```bash
git add README.md docs/debt/0001-require-verify-branch-protection.md
git commit -m "docs: record required verify protection"
```

### Task 3: Ship and re-prove the real branch

**Files:**

- No additional planned repository changes

**Interfaces:**

- Consumes: Tasks 1 and 2 plus the process-required spec and plan commits
- Produces: a green, mergeable real PR for issue #16

- [ ] **Step 1: Run final local verification**

```bash
just verify
git status --short --untracked-files=all
```

Expected: all checks pass and the feature worktree is clean.

- [ ] **Step 2: Push and open the real PR**

Push `feat/require-verify-main-check-16` and create a PR against `main`. The body
records the exact setting, the closed proof PR evidence, cleanup, local verification,
and recovery documentation, ending with `Closes #16`.

- [ ] **Step 3: Confirm the newly required real check**

Wait for the real PR's `verify` check, then require:

- `verify` from app ID `15368` is successful;
- the branch protection endpoint still reports the expected policy; and
- the PR is `CLEAN` / `MERGEABLE`.

Post the required `WORK:REVIEW` and hand-off trajectory annotations. Do not merge;
the campaign orchestrator owns that action.
