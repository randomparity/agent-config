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

## Provenance

target: scripts/check-skill-layout-test.sh
target: scripts/check-skill-layout.sh
tracker: #56
Raised by the adversarial review of issue #54 on branch
`feat/filter-test-suites-from-install-54`, 2026-08-03.
