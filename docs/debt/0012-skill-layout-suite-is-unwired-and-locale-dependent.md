# 0012 — The skill-layout suite is unwired and its portability rule is locale-dependent

## Status

Open
review-by: 2026-11-03

## Concern

`scripts/check-skill-layout-test.sh` is invoked by no recipe. It is absent from the
`Justfile` `test` recipe, `.pre-commit-config.yaml` shells out only to `just verify`,
and `.github/workflows/verify.yml` runs `just ci` — so nothing runs it in CI or in a
hook. The gate it guards, `skills-check`, does run.

Run bare it exits 1:

```
check-skill-layout-test: expected failure containing: content/skills/skill-01/café.md: path component is not portable ASCII
```

`validate_relative_path` in `scripts/check-skill-layout.sh` tests each path component
with `[[ "$component" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]`. Under `LANG=en_US.UTF-8`
the bracket expressions admit `é`, so the portability rule does not bite on a UTF-8
host and the suite's expected-failure case never fires. Verified pre-existing: the
same failure reproduces with `main`'s copy of `check-skill-layout.sh` and with this
branch's, so ADR 0025's edit to that file neither caused it nor changed it.

## Why deferred

ADR 0025 is about which assets reach an installed tree and which gates model that
boundary. The smallest honest fix here is a behavior change to an unrelated rule —
character-class matching in the path-portability check — and wiring the suite in
before that fix would turn `just verify` red, blocking a change that has nothing to
do with it. ADR 0025 touches `check-skill-layout.sh` only to add the `testdata`
exclusion to its deployment-rule scan, which is independent of the portability
rules above it.

## Non-regression boundary

ADR 0025 must not make this worse, and does not: it narrows only the
installed-config-root scan at the foot of the script, leaving
`validate_relative_path` and every other portability rule untouched, and it adds no
new caller of the suite. The suite's failure output is byte-identical before and
after. Anything that changes `validate_relative_path`, or that adds a rule relying
on ASCII-only path components, is outside that boundary and belongs with the fix.

## What would resolve it

Make the character-class test locale-independent — `LC_ALL=C` around the match, or a
byte-class rewrite of the pattern — confirm `./scripts/check-skill-layout-test.sh`
exits 0, then add it to the `Justfile` `test` recipe. Done when `just verify` runs
the suite and is green, and when reverting the locale fix turns it red.

Then close the recurrence rather than this instance of it: add a check that every
`*-test.sh` in the repository is reached by a recipe — `just test`, or `just records`
for `check-records-test.sh` — so the next unwired suite fails instead of hiding.
Suite wiring is hand-maintained across the `lint`, `format-check`, `format` and
`test` recipes, deliberately (ADR 0025 argues a glob would have concealed the
sibling-path breakage the moved suites exposed), but nothing today reports a suite
that no recipe names. Two instances have been found by accident: this one, and
`start-server-test.sh`, unrun from the day it was added until ADR 0025 moved it.
That check cannot land before the locale fix above, because it would go red on this
very suite.

That check is also the owner for making ADR 0025's six-place list checkable, which
it currently is not over two of its entries. Both are named in that record and
neither has a gate:

- `check-skill-layout.sh`'s `testdata` exclusion has no case and is inert on
  today's tree. Once this suite runs, add one — it already drives the script
  against a fixture root and already exercises the config-root rule.
- `stage_skills`'s entry-shaped filter is not exercised: reinstating `-type d`
  leaves `just verify` green, because the installer stages from the real
  repository and no plain file named `testdata` exists to inject. A case would
  copy the repository to a scratch tree, create such a file under one skill, run
  that copy's `install.sh` against a separate destination and assert absence —
  which needs a fixture-repo pattern `install-test.sh` does not have today.

One owner for both, rather than two records saying a site is unenforced.

### Criteria as of #56

Issue #56 closed the first paragraph above and one of the two unenforced sites.
The locale fix landed as explicit ASCII enumerations rather than an `LC_ALL=C`
subshell — a variable assignment cannot prefix the `[[` builtin, so pinning the
collation would have meant a subshell around every match. That is the same remedy
ADR 0023 chose for `tracker.sh`, so it needs no record of its own. The suite is
wired into the `Justfile` `test` recipe, `just verify` is green, and reverting the
enumerations to ranges turns it red under a territory UTF-8 locale. The
`check-skill-layout.sh` `testdata` exclusion now has a case, as this section
asked, plus a second case pinning the exclusion to `content/skills` so it cannot
be widened over roots that deploy verbatim.

The two deferrals that remain now have issues, and this record is Open as their
owner until both close:

- #59 — the gate asserting every `*-test.sh` is reached by a recipe. This is the
  recurrence, not the instance, and it could not land before the locale fix
  because it would have gone red on this very suite. That constraint is now gone.
- #60 — the fixture-repo case for `stage_skills`'s entry-shaped filter, the second
  of the two sites ADR 0025 names without a gate.

Resolve this record when both are merged. Neither is a prerequisite of the other.

Two further defects were found only because #56 ran the suite for the first time,
which is the argument for #59 rather than evidence against this record: the
`café.md` case had never fired, and PR #58's fail-closed guard for a missing
deployed content root had silently broken the suite's fixture, which did not create
`content/languages` or `content/references`.

## Provenance

target: scripts/check-skill-layout-test.sh
target: scripts/check-skill-layout.sh
tracker: #56
Raised by the adversarial review of issue #54 on branch
`feat/filter-test-suites-from-install-54`, 2026-08-03.
