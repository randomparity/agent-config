# 0032 — Every Shell Source Is Reached or an Identical Copy

## Status

Proposed

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
line is a Bash shebang must be reached by lint, format-check, and format.

Reuse ADR 0026's recomputed byte-identity clearance in each dimension. An unreached shell source is
covered when its bytes equal a reached source's bytes; the gate reports that clearance. This covers
the decision-record assets only while `just records` also enforces their identity with the reached
root copies.

Keep the inventory and recipe mapping explicit. A tracked shell source with whitespace in its path,
an empty inventory, a missing scanned recipe, or a dependency on a scanned recipe fails closed.

## Consequences

Adding a tracked shell source without wiring all three static-analysis recipes makes `just verify`
fail in the introducing commit. Extensionless Bash tools receive the same protection as `*.sh`
files. The gate still does not parse shell syntax or infer formatting flags; the recipes remain the
authority for those rules.

The checker performs more tracked-file and index reads, but the repository is small and the work is
local. Byte-identical copies avoid redundant lint and format invocations while their clearance stays
visible and recomputed.

## Considered & rejected

**Add a sibling shell-only checker.** Rejected because it duplicates the existing dry-run parsing,
recipe-independence checks, copy clearance, and diagnostics. The inventories differ, but the
reachability mechanism does not.

**Hardcode the five decision-record asset exclusions.** Rejected because an allowlist can outlive
the identity check that justifies it. Byte comparison makes the exception conditional on current
content and reports the reached twin.

**Require every shell source to be named directly.** Rejected because it repeats work for files that
`just records` proves are exact copies. Running the same content under the same static-analysis rule
adds cost without adding evidence.
