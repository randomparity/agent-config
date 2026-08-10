# 0032 — Every Shell Source Is Reached or an Identical Copy

## Status

> **Superseded by [0037](0037-verification-recipes-discover-shell-sources.md)** (2026-08-09)

Superseded (2026-08-09)

## Context

ADR 0026 requires every tracked `*-test.sh` suite to be reached by the recipes that
execute, lint, format-check, and format it. That gate deliberately enumerates suites only.
Issue #75 found the same silent omission outside suites: tracked shell sources could be named by
none of the three static-analysis recipes while `just verify` stayed green.

The repository's shell sources are both `*.sh` files and extensionless executables with Bash
shebangs. Five decision-record asset copies are intentionally not named directly because
`just records` byte-compares them with root copies that the static-analysis recipes reach.

## Decision

Extend the existing suite-coverage checker into a two-inventory recipe-coverage gate. Suites retain
the execution dimension. Every tracked `*.sh` file and every extensionless file whose indexed first
line selects Bash must be reached by lint, format-check, and format. An extensionless basename,
after one leading dot for a hidden filename is removed, contains no dot. Bash selection means a
direct interpreter token with basename `bash`, `env` followed immediately by `bash`, or `env -S`
followed by `bash`; arguments after Bash are allowed.

Keep ADR 0026's general recomputed byte-identity clearance for suite coverage. For the broader
shell-source inventory, permit only these asset/root pairs to use recomputed byte-identity
clearance:

- `content/skills/decision-records/assets/check-records.sh` and
  `.github/scripts/check-records.sh`
- `content/skills/decision-records/assets/check-records-test.sh` and
  `.github/scripts/check-records-test.sh`
- `content/skills/decision-records/assets/migrate-records.sh` and
  `.github/scripts/migrate-records.sh`
- `content/skills/decision-records/assets/profiles/adr.sh` and
  `.github/scripts/profiles/adr.sh`
- `content/skills/decision-records/assets/profiles/debt.sh` and
  `.github/scripts/profiles/debt.sh`

The gate reports each clearance. Every other tracked shell source must be named directly by each
recipe, including any future copy added beside these five without a separate decision.

Keep the inventory and recipe mapping explicit. A tracked shell source with whitespace in its path,
an empty inventory, a missing scanned recipe, or a dependency on a scanned recipe fails closed.

## Consequences

Adding a tracked shell source without wiring all three static-analysis recipes makes `just verify`
fail in the introducing commit. Extensionless Bash tools receive the same protection as `*.sh`
files. The gate still does not parse shell syntax or infer formatting flags; the recipes remain the
authority for those rules.

The checker performs more tracked-file and index reads, but the repository is small and the work is
local. The five byte-identical decision-record shell copies avoid redundant lint and format
invocations while their clearance stays visible and recomputed. A duplicate shell source elsewhere
receives no exemption merely because its content happens to match a reached file.

## Considered & rejected

**Add a sibling shell-only checker.** Rejected because it duplicates the existing dry-run parsing,
recipe-independence checks, copy clearance, and diagnostics. The inventories differ, but the
reachability mechanism does not.

**Exclude the five decision-record paths unconditionally.** Rejected because a path allowlist can
outlive the identity check that justifies it. The chosen fixed pair list bounds the exception, while
byte comparison still makes each clearance conditional on current content and reports the twin.

**Require every shell source to be named directly.** Rejected because it repeats work for files that
`just records` proves are exact copies. Running the same content under the same static-analysis rule
adds cost without adding evidence.

**Leave the suite-only gate unchanged.** Rejected because `statusline.sh` and `find-polluter.sh`
were outside lint, format-check, and format while `just verify` passed. Wiring those two files
without widening the inventory would leave the next non-suite omission equally silent.
