# 0037 — Verification recipes discover shell sources from Git

## Status

Accepted (2026-08-09)

## Context

ADR 0025 chose hand-enumerated file lists in the `Justfile` recipes: a glob would have
run the moved `testdata/` suites from their new paths without anyone noticing that one
resolved its subject as a sibling and broke. Enumeration's cost is that it can be
incomplete with no signal, and two omissions are on record (`docs/debt/0012`). ADR 0026
closed that gap with `scripts/check-suite-coverage.sh`, a gate that parses
`just --dry-run` output to prove every tracked suite is named by the recipes that execute,
lint, format-check, and format it; ADR 0032 extended the same gate to every tracked shell
source, with byte-identity clearance for the five decision-record asset twins.

That machinery — a 7.5 KB checker, a 332-line suite, twin-clearance rules, and two ADRs
of dry-run parsing rationale — exists only because the recipes enumerate. It tests the
wiring of the test suite rather than any behavior the repository ships, and it sits on an
unstable interface (`just --dry-run` output format). The defect class it covers is real,
but discovery removes the class instead of detecting it: a recipe whose subject set is
read from Git cannot forget a tracked file, because the file is how the recipe learns
scripts exist.

## Decision

The `lint`, `format-check`, `format`, and `test` recipes discover their subjects from the
Git index rather than naming files. `scripts/list-shell-sources.sh` prints every tracked
file whose name ends in `.sh` or whose first line is a Bash shebang — which covers the
extensionless helpers (`pre-push-hook`, the sdd-workspace tools, the preflight scripts)
that enumeration once named one by one — and classifies each as repository-default or
two-space for `shfmt -i 2`. The two-space list lives in that one helper: the vendored
brainstorming tree (ADR 0005's re-vendor argument), the `.github/scripts` record gate and
its byte-identical `decision-records` asset twins, and the two first-party sources that
predate the format gate.

`test` runs every tracked `*-test.sh`, excluding the two `check-records-test.sh` copies,
which `just records` already executes; running them under `test` as well would duplicate
the repository's largest suite for no new evidence. Discovery fails closed: an empty
shell-source or suite inventory is an error, not a green run over nothing.

`scripts/check-suite-coverage.sh`, its suite, and the `suites-check` recipe are deleted.
This record supersedes ADRs 0026 and 0032.

## Consequences

- Adding a tracked script or suite requires no recipe edit and cannot be unwired:
  `git ls-files` reads the index, so a file is covered from the moment it is staged,
  which is before the pre-commit hook runs.
- The byte-identity clearance machinery is gone. The decision-record asset twins are
  linted and format-checked directly; identical bytes under identical flags yield the
  gate's verdict without a clearance rule, at the price of a few redundant shellcheck
  and shfmt invocations.
- ADR 0025's original hazard is unchanged, not worsened: enumeration never protected
  against a suite resolving its subject as a sibling — the moved suites *were* wired and
  still broke — so discovery loses no protection that existed.
- An untracked spike is outside the gates, exactly as under the enumeration gate.
- The gates no longer depend on `just --dry-run` output, an interface `just` does not
  stabilize.

## Considered & rejected

- **Keep the enumeration and the coverage gate.** Rejected: the gate's entire subject is
  the enumeration's completeness. Once recipes discover, the gate proves a tautology at
  the cost of a checker, a suite, and a standing dependency on dry-run output.
- **Glob directly in the recipes without a helper.** Rejected: `*.sh` globs cannot reach
  the extensionless Bash executables, which is the omission ADR 0032 was written for, and
  the two-space classification would be duplicated across three recipes instead of owned
  in one place.
- **Run the records suite under `test` as well as `records`.** Rejected: it is the
  repository's largest suite and `just verify` runs both recipes; the second run adds
  minutes, not evidence.
- **Keep `suites-check` as a smoke assertion that discovery is non-empty.** Rejected:
  both discovery points already fail closed on an empty inventory, so the assertion would
  duplicate a check its subjects perform.
