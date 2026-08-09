# Shell File Recipe Coverage Design

## Scope

Issue #75 requires every tracked shell source to be named by the repository's lint,
format-check, and format recipes. The inventory includes `*.sh` files and extensionless files
whose first line is a Bash shebang. The execution dimension remains suite-only. The change also
wires the two remaining sources with two-space formatting:

- `agents/claude/shared/statusline.sh`
- `content/skills/systematic-debugging/find-polluter.sh`

The three extensionless subagent-driven-development scripts already use the repository-default
indentation and are already wired by PR #74. This change does not reformat or regroup them. It
also does not directly wire the five decision-record asset copies; `just records` enforces their
byte identity with linted and formatted root copies.

## Approaches

The chosen approach extends `scripts/check-suite-coverage.sh` with a shell-source inventory and
reuses its dry-run path collection. Suites use the existing four dimensions and retain their
general byte-identity clearance. Shell sources use lint, format-check, and format; their copy
clearance is limited to the five explicit decision-record asset/root pairs named in ADR 0032 and
requires reached, byte-identical `.github/scripts/` twins. This keeps one implementation of the
fragile `just --dry-run` interpretation without creating a directory-wide duplicate-content
exemption.

A sibling shell-only checker would isolate the new policy, but it would duplicate dry-run parsing,
standalone-recipe checks, diagnostics, and byte-copy handling. Hardcoded exclusions for the five
asset copies would be shorter, but could remain green after `just records` stopped enforcing an
identity. Both alternatives are rejected in ADR 0032.

## Design

The checker builds two NUL-safe arrays from tracked paths. The suite array keeps the existing
`*-test.sh` enumeration. The shell array includes every `*.sh` path and every extensionless path
whose indexed first line names Bash as its interpreter. Each inventory fails closed when empty and
rejects whitespace in paths because recipe output is intentionally tokenized by words.

Dimension metadata identifies both the inventory and the recipes to scan. The execution dimension
checks suites only. Lint, format-check, and format check the broader shell inventory. For each
dimension, an unreached suite may be cleared by any identical reached suite as ADR 0026 specifies.
An unreached shell source is cleared only when it is one of ADR 0032's five named decision-record
asset paths and its named `.github/scripts/` twin is reached and byte-identical. Diagnostics say
`suite` for execution failures and `shell file` for the three source dimensions.

The `Justfile` adds the two remaining files to `lint` and to a documented `shfmt -i 2` group in
`format-check` and `format`. No shell source content changes are expected because both already pass
those exact commands.

## Failure Handling

Missing tools, missing scanned recipes, recipe dependencies, empty inventories, unsupported
whitespace paths, missing tracked files, and unreached sources remain fail-closed with a path and
actionable recipe guidance. An indexed extensionless path that cannot be read cannot silently
disappear from the shell inventory; enumeration reports the read failure.

## Testing

The fixture gains an ordinary non-suite `*.sh` file, an extensionless Bash-shebang file, and a
byte-identical decision-record-style shell copy governed through a reached twin. A duplicate outside
that mapped asset path must fail. The initial fixture must pass. Mutations
remove each shell file from lint, format-check, and format in turn and assert the gate fails with the
path and dimension. A non-Bash extensionless file remains outside the inventory. Existing suite
execution, copy, pathname, dependency, and empty-enumeration cases continue to pass.

The implementation follows test-first development: add the new fixture and red mutations, prove the
current checker misses them, then implement the inventory split and recipe wiring. `just verify` is
the final local gate.
