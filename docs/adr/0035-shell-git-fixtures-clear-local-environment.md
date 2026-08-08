# 0035 — Shell Git Fixtures Clear the Local Git Environment at Suite Entry

## Status

Proposed

## Context

Git hooks export repository-local environment variables. Those variables override directory
selection by `git -C`, so fixture initialization, configuration, indexing, commits, and root
discovery can target the hook's repository instead of a disposable fixture. The affected
suite files ship in root, canonical-skill, installed-skill, and mirrored-asset layouts.

Git exposes the variables it treats as repository-local through
`git rev-parse --local-env-vars`. A manually maintained subset can omit config, object,
replacement, or future selectors.

## Decision

The six shell suite files in issue #65 clear every variable named by
`git rev-parse --local-env-vars` once, immediately after enabling strict shell mode and before
discovering roots or touching fixtures:

- `.github/scripts/check-records-test.sh`
- `content/skills/decision-records/assets/check-records-test.sh`
- `content/skills/brainstorming/scripts/testdata/start-server-test.sh`
- `content/skills/github-tracking/assets/testdata/tracker-test.sh`
- `content/skills/subagent-driven-development/scripts/testdata/sdd-workspace-test.sh`
- `scripts/check-suite-coverage-test.sh`

The loop is suite-local. Standalone suites do not source a shared helper solely for this
boundary. Mirrored suite assets carry byte-identical copies.

Hook-environment regression tests use only disposable common repositories and linked
worktrees. After each suite they compare common-repository config and resolved identity,
each branch's HEAD and index, README contents, working-tree status, and the full external
worktree list with snapshots taken before the suite ran.

## Consequences

Fixture Git commands and root discovery obey their explicit directories under hook and
linked-worktree execution. New local selectors reported by Git are cleared without a
source edit in these six files. Each suite repeats a short boundary stanza, and a Git
executable is required before suite path discovery; every affected suite already requires
Git for its fixtures. A future fixture suite is not automatically governed by this record;
it needs its own isolation review when it is added.

## Considered & rejected

**Unset a fixed list.** This is readable but drifts from Git's actual list and has already
omitted configuration and replacement selectors.

**Wrap each fixture Git command with `env -u`.** This duplicates policy at every call site,
misses non-command root discovery, and regresses when a suite adds a Git operation.

**Source a shared helper.** The suites do not share one stable installed path. Adding that
dependency would make standalone test execution depend on repository packaging structure for
a loop small enough to keep at each boundary.

**Do nothing and rely on CI.** Ordinary CI does not reproduce hook-local Git variables, and
the known failure occurs specifically while a developer commits.
