# Installed tree membership — implementation plan

Issue: <https://github.com/randomparity/agent-config/issues/106>
Spec: [2026-08-10-installed-tree-membership-design.md](../specs/2026-08-10-installed-tree-membership-design.md)
Record: [0045](../../adr/0045-installed-trees-declare-their-membership.md)
Branch: `feat/gate-installed-tree-membership-106`, off `main`.
Guardrail: `just verify`, run bare. CI runs `just ci`, which calls it.

The spec fixes the contract in full — messages, exit codes, enumeration, comparison, suite
rows. This plan sequences the work and records what each task must not get wrong. Where the
two disagree, the spec wins.

## Repository conventions that bind every task

- Tab indentation for new shell sources; `shfmt` and `shellcheck` run over everything
  `scripts/list-shell-sources.sh` discovers, which is any tracked `*.sh` or Bash-shebang file.
  No recipe edit is needed for discovery.
- `just test` runs every tracked `*-test.sh` via `git ls-files`, so the new suite must be
  **staged** before it is discovered.
- Both CI legs matter: `ubuntu-latest` and `macos-latest`, the latter on system Bash 3.2 with
  BSD `sed` and BSD `find`. No `declare -A`, no `mapfile`, no GNU-only `find` behavior.
- Guardrails run bare — no pipes, no `|| true`.
- `just records` locally reports `BASE_SHA unset — validating records only`. No merged record
  is touched by this branch, so that gap does not bite; do not touch `docs/adr/0041-*.md`.

## Task 1 — the gate

**File:** `scripts/check-deployed-membership.sh` (new, executable, tab-indented).

Implement the contract in the spec's *The gate* section: the two literals, the tree filter,
the enumeration, the comparison, the verdict table, the streams, the emission order.

The points most likely to be got wrong, each of which the suite pins:

- `export LC_ALL=C` near the top, for the whole run — not per-`sort`. `comm` collates by
  locale too, and C-sorted input read under another locale makes it emit spurious lines.
- Filter trees with `-d` **and not** `-L`. `test -d` dereferences, so a tree replaced by a
  symlink to a directory would otherwise survive and `find` would print the tree path itself.
- Pass tree paths to `find` **without** a trailing slash; a trailing slash forces dereference.
- When no tree survives, do not invoke `find` at all. GNU `find` with no path operand defaults
  to `.`; BSD `find` errors. Both are wrong answers.
- Capture `find`'s exit status directly, not through a pipeline, so a failed scan cannot read
  as an empty one. A failed scan is exit 2, and because enumeration completes before any
  comparison, no finding exists yet to be swallowed.
- A non-regular member is `non-regular-member` **in addition to** its membership verdict: it
  still counts as present, so a declared symlink reports `non-regular-member` alone and an
  undeclared one reports `unexpected-member` and `non-regular-member` both.
- Findings and faults to stderr; the `ok` summary to stdout; nothing else on stderr on a
  green run.
- Accept an optional repository-root argument, as the sibling gates do — it is how the suite
  points the checker at a fixture.

**Acceptance:** `shellcheck` and `shfmt -d` clean; running it bare in the worktree prints the
`ok` summary with the real counts and exits 0.

## Task 2 — the suite

**File:** `scripts/check-deployed-membership-test.sh` (new, executable, tab-indented).

Implement every row of the spec's suite table, with the two departures from
`check-shared-standards-test.sh` the spec requires: separate stdout/stderr capture, and an
`assert_findings` helper that compares the whole stderr sequence in order.

- Build the fixture from the **index**: `git -C "$ROOT" ls-files -z -- <trees>` into
  `git -C "$ROOT" checkout-index --prefix="$FIXTURE/" -z --stdin -f`, after aborting with a
  named message if `git -C "$ROOT" ls-files -u -- <trees>` reports an unmerged path.
- Derive the expected member count from what the fixture build enumerated. Do not write `7`.
- Guard the `mktemp -d` cleanup by path prefix, as the sibling suite does.
- The unreadable-tree row must skip when running as root, and **announce the skip on stderr**
  — it is the only executable evidence that a fault never swallows a finding.
- The order-asserting row must also run under a non-`C` caller locale, with its expected
  sequence still built under `LC_ALL=C`. Without that, every checker invocation inherits the
  suite's own `LC_ALL=C` and the gate's export is never what makes the row pass — the pin
  would ship unfalsified, and Task 3's mutation of it could not redden anything.

**Acceptance:** `./scripts/check-deployed-membership-test.sh` passes; every row present.

Commit Tasks 1 and 2 before Task 3, so Task 3's mutations are revertible.

## Task 3 — prove the suite bites

Tasks 1 and 2 are committed by now, so each mutation is undone with
`git restore scripts/check-deployed-membership.sh` rather than by hand — an untracked file has
nothing to restore to, and "reverted" would not be a state anyone could check.

Break the gate deliberately and confirm the suite reddens, one mutation at a time: drop the
`! -L` from the tree filter, drop the `export LC_ALL=C`, and make the run exit at its first
finding. Each must fail a named row. A suite that stays green through those is not testing
what it claims.

**Acceptance:** each of the three mutations reddens the suite, naming which row caught it; and
after the last `git restore`, `git status --short` and `git diff` are both empty.

## Task 4 — wiring

**File:** `Justfile`. This branch is the only one authorized to edit it this wave.

Add:

```
membership-check:
  ./scripts/check-deployed-membership.sh
```

and put `membership-check` in the `verify` dependency list **immediately after
`commit-check`**, ahead of every content gate. Not a relative landmark: `check-skill-layout.sh`
exits on a missing `content/languages` or `content/references` root and `skills-check` already
precedes `shared-standards-check`, so placing it only ahead of the latter would still let a
sibling fault preempt the membership answer for two of the three trees. Not in `commit-check`
itself.

**Acceptance:** `just membership-check` runs; `just verify` reaches it.

## Task 5 — installer cross-reference

**File:** `install.sh`, comments only. One comment in `install_common_content` covering its
`content/languages` and `content/references` calls, one at the `agents/bob/shared/rules` call
in `install_bob`. Each names the manifest so a reader adding a fourth directory source finds
the gate.

Do not touch `merge_json_settings` or its call sites — issue #110 owns those.

**Acceptance:** no behavior change; `install-test.sh` still passes.

## Task 6 — full verification

Stage everything first, so `just test` discovers the new suite. Then run `just verify` bare.

An exit code alone cannot show criterion (4) was met: `lint`, `format-check` and `test` all
discover through `git ls-files`, so staging the gate and the `Justfile` while leaving the
suite unstaged produces a fully green `just verify` in which the new suite never ran, and
nothing in the output says so.

**Acceptance:** `git status --short` shows every new and changed file staged; the `just verify`
output contains the `== scripts/check-deployed-membership-test.sh` line the `test` recipe
prints; and the run exits 0. Report that line as the evidence for automatic discovery, and
report the real result whatever it is.

## Rollback

Every task is additive except the `Justfile` and `install.sh` edits, both of which are small
and revertible on their own. Nothing here changes what the installer deploys, so a revert of
the branch restores the prior state exactly.
