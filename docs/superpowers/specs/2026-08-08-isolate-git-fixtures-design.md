# Isolate Git Fixture Suites from Hook Environments

## Scope

Issue #65, including closed duplicate #66, requires every tracked shell suite that
constructs Git repositories to ignore repository-local Git variables inherited from a
hook. The change covers the six existing suite files, a safe linked-worktree-shaped
regression harness, and the `just` wiring needed to run that proof. It excludes sibling
campaign worktrees, production workflow behavior, and unrelated test refactors.

## Problem

Git hooks export repository-local variables such as `GIT_DIR`, `GIT_WORK_TREE`, and
`GIT_INDEX_FILE`. Those variables take precedence over `git -C <fixture>`, so an otherwise
disposable fixture command can instead modify the common repository, its active branch,
or another linked worktree. A fixed list is insufficient because Git reports additional
local selectors, including config and object-database variables, and that list can vary by
Git version.

The six existing suite files are:

- `.github/scripts/check-records-test.sh`
- `content/skills/decision-records/assets/check-records-test.sh`
- `content/skills/brainstorming/scripts/testdata/start-server-test.sh`
- `content/skills/github-tracking/assets/testdata/tracker-test.sh`
- `content/skills/subagent-driven-development/scripts/testdata/sdd-workspace-test.sh`
- `scripts/check-suite-coverage-test.sh`

The two decision-record paths are mirrored assets and must remain byte-identical.

## Approaches

### Selected: scrub Git's reported local environment at suite entry

Each suite asks `git rev-parse --local-env-vars` for the complete local-variable set and
unsets every returned name before it discovers roots or creates fixtures. The small loop is
repeated in each standalone suite because the installed suites do not share a stable helper
path. This clears current and future Git-reported selectors once, before any fixture action.

### Rejected: wrap individual fixture commands

Wrapping each `git init`, `git config`, `git add`, and `git commit` leaves directory-based
root discovery and newly added Git commands exposed. It also makes omissions likely as the
suites evolve.

### Rejected: source one repository helper

A shared helper would reduce repeated lines but add a runtime path dependency across root,
canonical skill, installed-skill, and mirrored-asset layouts. The suites are intentionally
standalone, and the repeated isolation boundary is smaller than that coupling.

## Design

The scrub runs immediately after `set -euo pipefail` in each existing suite. It reads one
variable name per line, ignores an empty line defensively, and calls Bash `unset` with a
quoted name. The mirrored decision-record suite receives the identical edit in both copies.

A new root regression suite creates a temporary common repository and two linked worktrees.
It records common-repository config and identity, branch tips, indexes, README contents,
statuses, and the complete worktree list. For each affected suite it then supplies a
hook-shaped child environment containing absolute `GIT_DIR`, `GIT_COMMON_DIR`,
`GIT_WORK_TREE`, and `GIT_INDEX_FILE` values from one linked worktree. It also sets
`GIT_CONFIG` to the disposable common repository's config file. That representative
Git-reported selector outside the familiar four makes a fixed four-variable scrub fail by
changing the snapshotted common identity. Each child runs from the source checkout while all
Git targets remain disposable. After every child, the harness compares the recorded state
with fresh observations and fails with the suite path and changed surface if any common or
worktree state moved.

The harness clears its own inherited local Git environment before creating the disposable
ambient repository. It is added to `just test`, so both bare verification and the actual
pre-commit path exercise it. The existing affected suites still run directly in `just test`;
the regression's hook-shaped executions are additional evidence, not replacements.

## Failure behavior

Failure is immediate and names the suite and ambient surface that changed. Temporary state is
removed on success or failure. The harness never points a child at the developer repository,
so a red test demonstrates the original mutation only against disposable state.

## Verification

TDD proof first runs the new harness on unchanged suite files and observes a safe failure
against the disposable ambient repository. After the suite-entry scrubs are added, the
harness and all six affected suite files pass. `cmp` proves the decision-record mirrors are
byte-identical, `just verify` proves repository guardrails, and an ordinary `git commit`
without `--no-verify` proves the installed pre-commit path can run without changing common
config or linked worktrees.

## Threat model

### Boundary inventory

The existing boundary is a hook-controlled process environment entering standalone test
suites. The change adds no production boundary. The regression deliberately constructs that
environment only for children whose Git repository is a disposable linked worktree.

### Actor model

The relevant actor is a local Git hook or automation runner supplying repository-local Git
selectors. The suite trusts Git itself to enumerate the selector names and trusts only the
temporary directory it creates as a mutation target.

### Controls

- Every Git-reported local variable is removed before suite root discovery or fixture work.
- The poisoned environment includes `GIT_CONFIG`, so the proof rejects a scrub limited to
  directory, common-directory, worktree, and index selectors.
- The regression uses absolute paths inside one owned temporary directory.
- State snapshots cover common config/identity, refs, indexes, working files, status, and all
  external worktrees after each affected suite.
- Existing shell lint, formatting, mirrored-asset, and full verification gates remain active.

### Out of scope

This does not sandbox arbitrary commands or protect against a malicious test that explicitly
targets the developer repository. It prevents accidental target redirection through Git's
documented repository-local environment channel.

## Decision record

The suite-entry boundary and rejected shared-helper alternative are recorded in
[ADR 0035](../../adr/0035-shell-git-fixtures-clear-local-environment.md).
