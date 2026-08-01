# 0006 — The record gate remains editable by the change it gates

## Status

Open
review-by: 2026-11-01

## Concern

The root record gate executes the checker and workflow from the pull request's own tree.
The adopted checker detects deletion or replacement of its files, while required branch
protection now prevents a pull request that removes the `verify` workflow from merging.
Those changes resolve the deletion half of
[predecessor debt 0003](https://github.com/randomparity/claude-config/blob/main/docs/debt/0003-gate-cannot-detect-its-own-neutering.md),
but not its edit vector: the same pull request can change the checker to accept content the
base version would reject, and the required check then reports success.

Repository configuration guarantees that the named check must succeed. It cannot guarantee
what a pull-request-controlled implementation of that check evaluates. Human review remains
the only protection against a coordinated edit that weakens the checker and its tests.

## Why deferred

Closing the remaining boundary requires a trusted execution source outside the pull request,
such as a protected reusable workflow or externally pinned gate. That changes the public
adoption and update model and needs a separate design. Re-evaluate by 2026-11-01, one quarter
after this migration, so the residual is reviewed alongside evidence from gate adoption.

## Non-regression boundary

The checker continues to detect deletion, untracking, symlink replacement, and undeclared
renames of known gate files. Documentation must continue to state that required repository
configuration protects check presence, while review—not the PR-controlled gate—protects
against a coordinated edit to the checker and suite.

## What would resolve it

Run the gate implementation from a trust boundary a pull request cannot modify and prove that
a pull request which weakens or deletes its in-tree checker cannot satisfy the required check.
Update the adoption documentation to identify the trusted source and recovery path.

## Provenance

target: .github/workflows/verify.yml
target: .github/scripts/check-records.sh
target: content/skills/decision-records/assets/check-records.sh
Reproduced against issue #12's current root gate on 2026-08-01. Issue #7 and issue #16
resolved workflow disappearance through the required `verify` check; checker edits remain
pull-request-controlled.
