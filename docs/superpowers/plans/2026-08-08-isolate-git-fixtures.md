# Isolate Git Fixture Suites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent repository-local Git variables inherited from hooks from redirecting any
of the six existing fixture suites into the developer repository.

**Architecture:** Each standalone suite clears Git's own reported local-variable set at
entry. A root regression suite executes all six under a disposable linked-worktree-shaped
environment and compares explicit common-repository and worktree snapshots.

**Tech Stack:** Bash 3.2-compatible shell, Git CLI, `cmp`, `diff`, `just`, `shellcheck`,
`shfmt`, and `prek`.

## Global Constraints

- BASE_BRANCH is `main`; the guardrail is `just verify`.
- Work only in `feat/isolate-git-fixtures-65` and its external worktree.
- Do not touch sibling issue worktrees or merge the PR.
- Use every name emitted by `git rev-parse --local-env-vars`, never a fixed list.
- Keep `.github/scripts/check-records-test.sh` and
  `content/skills/decision-records/assets/check-records-test.sh` byte-identical.
- The regression may mutate only repositories below its owned temporary directory.
- Do not use `--no-verify`; the actual pre-commit path is part of acceptance.
- Design commits wait until the unsafe hook path is fixed, then stage explicit paths.

---

### Task 1: Add the disposable hook-environment regression

**Files:**

- Create: `scripts/git-fixture-isolation-test.sh`
- Modify: `Justfile`

**Interfaces:**

- Consumes: the six suite paths enumerated by ADR 0035 and Git linked-worktree metadata.
- Produces: a standalone zero/non-zero regression suite wired into `just test`.

- [x] **Step 1: Write the failing regression harness**

Create a strict-mode Bash suite that first clears its own inherited local Git variables,
then creates an owned directory with `mktemp -d`, immediately installs an `EXIT` cleanup
trap that validates the path still has the harness prefix before using `rm -R`, and creates
a repository with a committed README and two linked worktrees below it. Captured child
output must be printed before an assertion returns non-zero so cleanup does not erase the
diagnosis. Define these operations explicitly:

```bash
clear_local_git_env() {
  local variable
  while IFS= read -r variable; do
    [ -n "$variable" ] || continue
    unset "$variable"
  done < <(git rev-parse --local-env-vars)
}

snapshot_state() {
  local destination=$1 path
  mkdir -p "$destination"
  git --git-dir="$common_dir" config --local --list --show-origin \
    >"$destination/common-config"
  git -C "$ambient" config user.name >"$destination/user-name"
  git -C "$ambient" config user.email >"$destination/user-email"
  git -C "$ambient" worktree list --porcelain >"$destination/worktrees"
  for path in "$ambient" "$worktree_one" "$worktree_two"; do
    snapshot_worktree "$path" "$destination/$(basename "$path")"
  done
}
```

`snapshot_worktree` must record `rev-parse HEAD`, `ls-files --stage`,
`status --porcelain=v1 --untracked-files=all`, and `cksum README.md`. For each suite, invoke
it with absolute linked-worktree values for `GIT_DIR`, `GIT_COMMON_DIR`, `GIT_WORK_TREE`,
and `GIT_INDEX_FILE`, plus `GIT_CONFIG=$common_dir/config`. Capture its output, snapshot
again even when it exits non-zero, compare every snapshot file with `diff -ru`, and name
the suite and changed state on failure.

Run these exact paths:

```bash
suites=(
  content/skills/subagent-driven-development/scripts/testdata/sdd-workspace-test.sh
  content/skills/github-tracking/assets/testdata/tracker-test.sh
  content/skills/brainstorming/scripts/testdata/start-server-test.sh
  scripts/check-suite-coverage-test.sh
  .github/scripts/check-records-test.sh
  content/skills/decision-records/assets/check-records-test.sh
)
```

Add `./scripts/git-fixture-isolation-test.sh` to the `test` recipe. Existing `scripts/*.sh`
globs already put it under lint and format gates.

- [x] **Step 2: Run the regression and verify RED safely**

Run: `./scripts/git-fixture-isolation-test.sh`

Expected: non-zero against unchanged suites, naming the first affected suite or an ambient
state difference. Confirm all paths named by the failure are below the harness temporary
directory and `git status`/config/HEAD/index/README in this worktree and sibling worktrees
remain unchanged.

- [x] **Step 3: Do not commit the red test**

The installed hook is the defect under test. Keep the failing harness uncommitted until Task
2 makes the hook path safe.

### Task 2: Clear Git's reported local environment in all six suites

**Files:**

- Modify: `.github/scripts/check-records-test.sh`
- Modify: `content/skills/decision-records/assets/check-records-test.sh`
- Modify: `content/skills/brainstorming/scripts/testdata/start-server-test.sh`
- Modify: `content/skills/github-tracking/assets/testdata/tracker-test.sh`
- Modify: `content/skills/subagent-driven-development/scripts/testdata/sdd-workspace-test.sh`
- Modify: `scripts/check-suite-coverage-test.sh`

**Interfaces:**

- Consumes: newline-separated variable names from `git rev-parse --local-env-vars`.
- Produces: suite processes with no inherited repository-local Git selector before any root
  discovery or fixture operation.

- [x] **Step 1: Add the minimal entry boundary**

Immediately after `set -euo pipefail`, use the suite's existing indentation style:

```bash
while IFS= read -r variable; do
  [ -n "$variable" ] || continue
  unset "$variable"
done < <(git rev-parse --local-env-vars)
```

Replace the fixed unset list in `scripts/check-suite-coverage-test.sh`. Update the root
decision-record suite first, then copy it byte-for-byte to the canonical skill asset.

- [x] **Step 2: Run the focused GREEN proof**

Run the six suites directly, then run `./scripts/git-fixture-isolation-test.sh`.

Expected: every direct suite and every hook-shaped child exits zero; the harness reports no
snapshot difference. Run
`cmp .github/scripts/check-records-test.sh content/skills/decision-records/assets/check-records-test.sh`.

- [x] **Step 3: Run repository guardrails**

Run: `just verify`

Expected: exit 0 with no warnings.

- [x] **Step 4: Snapshot the real common repository and external worktrees**

Before staging, record the common repository's local config and resolved identity, the full
`git worktree list --porcelain`, and for every listed worktree except this feature worktree:
HEAD, `git ls-files --stage`, README checksum, and
`git status --porcelain=v1 --untracked-files=all`. Save these artifacts outside the repository.
Record this feature branch's current HEAD separately.

- [x] **Step 5: Commit the complete safety fix without bypassing hooks**

`prek` stashes unstaged changes before checking a commit, so the first verified commit must
contain every path that makes the hook safe. Stage the six suites, harness, and `Justfile`
explicitly and commit:

```bash
git add Justfile scripts/git-fixture-isolation-test.sh \
  scripts/check-suite-coverage-test.sh \
  .github/scripts/check-records-test.sh \
  content/skills/decision-records/assets/check-records-test.sh \
  content/skills/brainstorming/scripts/testdata/start-server-test.sh \
  content/skills/github-tracking/assets/testdata/tracker-test.sh \
  content/skills/subagent-driven-development/scripts/testdata/sdd-workspace-test.sh
git commit -m "fix: isolate Git fixture suites from hook state"
```

The ordinary commit must run the installed pre-commit hook. After it succeeds, confirm this
feature branch alone advanced to the new commit. Recreate the Step 4 snapshot for the common
config/identity, complete worktree list, and every other worktree's HEAD, index, README, and
status; compare it byte-for-byte with the pre-commit snapshot.

- [x] **Step 6: Prove the committed regression bites**

Use `apply_patch` to remove only the new scrub stanza from the committed, non-mirrored
`content/skills/github-tracking/assets/testdata/tracker-test.sh`. Run the harness and confirm
it fails safely against the disposable linked-worktree environment. Immediately run
`git restore content/skills/github-tracking/assets/testdata/tracker-test.sh` to recover the
known committed fix even if the test command returned non-zero, then rerun the harness green
and confirm `git status` shows no modification to that suite.

- [x] **Step 7: Commit the reviewed design artifacts**

With the safety fix now present in the staged commit seen by `prek`, stage the reviewed spec,
ADR, and plan explicitly and commit through the hook:

```bash
git add docs/adr/0035-shell-git-fixtures-clear-local-environment.md \
  docs/superpowers/specs/2026-08-08-isolate-git-fixtures-design.md \
  docs/superpowers/plans/2026-08-08-isolate-git-fixtures.md
git commit -m "docs: design Git fixture environment isolation"
```

Confirm the second commit advances only this feature branch and repeat the exact comparison
of common config/identity, complete worktree list, and every other worktree's HEAD, index,
README, and status.

### Task 3: Verify the shipped branch state

**Files:**

- Verify only: all Task 1 and Task 2 paths.

**Interfaces:**

- Consumes: committed branch diff against `main`.
- Produces: fresh evidence for review and PR shipping.

- [x] **Step 1: Review the diff and paths**

Run `git diff --check main...HEAD`, inspect `git diff --stat main...HEAD`, and confirm no
sibling-worktree path or unrelated file appears.

- [x] **Step 2: Run final verification**

Run the affected suites, the hook-shaped harness, `cmp` for mirrored assets, and
`just verify` again. Confirm the worktree is clean.

- [x] **Step 3: Hand off to branch review**

Record branch `feat/isolate-git-fixtures-65`, base `main`, guardrail `just verify`, and any
open finding artifact paths for the enclosing `$work-issue` review phase.
