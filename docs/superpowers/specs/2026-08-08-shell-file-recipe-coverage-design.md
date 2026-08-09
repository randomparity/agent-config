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
`*-test.sh` enumeration. A basename is extensionless when, after removing one leading dot used for
a hidden filename, it contains no dot. Thus `tool` and `.hook` are extensionless, while `tool.py`
and `.hook.local` are not. The shell array includes every `*.sh` path and every extensionless path
whose indexed first line matches one of these Bash shebang forms after zero or more ASCII space or
tab bytes following `#!`:

- a direct interpreter token whose basename is `bash`, such as `#!/bin/bash`;
- an `env` interpreter followed immediately by `bash`, such as `#!/usr/bin/env bash`; or
- an `env` interpreter followed by `-S` and then `bash`, such as
  `#!/usr/bin/env -S bash -e`.

Interpreter tokens are separated by one or more ASCII space or tab bytes. Arguments after the Bash
token do not change classification. A later `bash` argument to another interpreter, a command such
as `not-bash`, or an extensionless file without a shebang does not enter the inventory. Each
inventory fails closed when empty and rejects whitespace in paths because recipe output is
intentionally tokenized by words. Indexed first-line capture is limited to 4,096 characters while
the producer is drained. The bounded prefix is sufficient to classify ordinary shebangs without
retaining memory proportional to a contributor-controlled blob; an overlong non-Bash line remains
outside the inventory rather than creating policy for unrelated extensionless data.

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
actionable guidance. An indexed extensionless path that cannot be read cannot silently disappear
from the shell inventory; enumeration reports the read failure.

## Threat Model

The widened boundary is repository-contributor-controlled Git index data: tracked pathnames and the
first line of extensionless blobs enter a local developer/CI gate. Paths are NUL-enumerated, passed
to Git as one quoted argument, and rejected when a classified shell path contains whitespace.
First-line input is captured up to 4,096 characters with an anchored allowlist of Bash interpreter
forms; the remainder is drained so producer failures remain visible without unbounded Bash memory.

Existing boundaries are Justfile dry-run text and byte comparison. The checker never evaluates
dry-run text as shell code; ADR 0026 governs its word-tokenization constraint. Non-suite copy
clearance maps five literal asset paths to five literal root twins, then requires both current
recipe reachability and `cmp` equality. The actors are repository contributors who control proposed
tracked content and the local or CI job running `just verify`; no network, credential, privilege, or
tenant boundary is present.

Out of scope are a compromised Git/Just/ShellCheck/shfmt toolchain and the pre-existing glob
behavior of dry-run word collection documented by ADR 0026. A contributor can propose changes to
the checker or Justfile itself, but ordinary repository review and the mutation suite govern that
code-change boundary rather than runtime authorization.

## Testing

The fixture gains an ordinary non-suite `*.sh` file, an extensionless Bash-shebang file, and a
byte-identical decision-record-style shell copy governed through a reached twin. A duplicate outside
that mapped asset path must fail. Independently named positive extensionless fixtures cover direct
Bash, `env bash`, and `env -S bash`; a hidden Bash file; whitespace between `#!` and `env bash`;
trailing arguments after direct Bash and `env bash`; and a trailing argument after `env -S bash`.
Near misses cover another interpreter, `not-bash`, a later Bash argument, and a hidden basename with
a later extension dot. Each positive fixture has its own removal mutation proving the gate reports
that fixture as uncovered. The initial fixture must pass. Mutations also remove each ordinary shell
file from lint, format-check, and format in turn and assert the gate fails with the path and
dimension. Empty and large non-Bash indexed files prove bounded reads do not create false failures;
a fixture whose non-Bash first line exceeds 4,096 characters must remain a bounded near miss.
Existing suite execution, copy, pathname, dependency, and empty-enumeration cases continue to pass.

The implementation follows test-first development: add the new fixture and red mutations, prove the
current checker misses them, then implement the inventory split and recipe wiring. `just verify` is
the final local gate.
