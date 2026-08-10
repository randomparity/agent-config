# Installed tree membership — design

Issue: <https://github.com/randomparity/agent-config/issues/106>
Record: [0045](../../adr/0045-installed-trees-declare-their-membership.md)

## Problem

`install_managed_path` ends in `cp -pR`. When its source is a directory the whole subtree
lands in the agent's configuration directory. Four call sites pass a directory:

| call site | source tree | installs to | reaches |
|---|---|---|---|
| `install.sh` `install_bob` | `agents/bob/shared/rules` | `~/.bob/rules` | Bob |
| `install.sh` `install_common_content` | `content/languages` | `<config>/languages` | all three |
| `install.sh` `install_common_content` | `content/references` | `<config>/references` | all three |
| `install.sh` `install_<agent>` | staged `content/skills` | `<config>/skills` | all three |

No gate counts the entries of any of them. `check-shared-standards.sh` names one file inside
the rules tree; `check-deployed-references.sh` scans the trees for what a deployed file may
say. A file dropped into one of these directories therefore installs into every user's global
agent configuration with nothing asking whether it belongs. Record 0041 disclosed this as an
open residual.

`content/skills` is already shape-gated by `check-skill-layout.sh`: every child must be a
skill directory, symlinks and non-regular files are forbidden anywhere under it, and path
components are constrained. It is also the tree whose growth is routine. It stays out of this
design; the other three are in.

## Goal

A file appears in `agents/bob/shared/rules`, `content/languages` or `content/references` only
if a manifest declares it, and `just verify` is red until that is true in both directions.

## Non-goals

- Changing what `install.sh` deploys, or how. This adds detection only.
- Gating `content/skills` membership, or the contents of any listed file.
- Detecting a *new* wholesale-installed tree added to `install.sh` and not to the manifest.
  Nothing can, short of parsing the installer; a comment at each call site is the coupling.

## The gate

`scripts/check-deployed-membership.sh [repository-root]`, message prefix
`deployed-membership:`. The optional argument names a repository root to check instead of the
script's own, which is how the suite points it at a fixture — the same contract
`check-shared-standards.sh` and `check-deployed-references.sh` offer.

### Data

Two literals in the script:

- the declared trees, repo-relative: `agents/bob/shared/rules`, `content/languages`,
  `content/references`;
- the manifest, a newline-delimited list of repo-relative paths, one per declared member.

At the time of writing the manifest holds seven entries: the one rules file, five language
references, and one orchestration reference.

### Enumeration

Every entry under a declared tree that is not a directory is a member: regular files,
symlinks, and dot-prefixed and gitignored files alike, because `cp -pR` copies all of them.
`find <trees> ! -type d -print0` produces exactly that set and has no ignore logic to defeat,
which is why it is used here in place of the repository's usual `rg`.

### Comparison and verdicts

The enumerated set and the manifest are both sorted under `LC_ALL=C` and compared in both
directions.

| status | condition | message |
|---|---|---|
| 0 | the two sets are equal | `deployed-membership: ok (<n> declared members across <m> installed trees)` |
| 1 | present, not declared | `deployed-membership: unexpected-member: <repo-relative path>` |
| 1 | declared, not present | `deployed-membership: missing-member: <repo-relative path>` |
| 2 | more than one argument | `usage: check-deployed-membership.sh [repository-root]` |
| 2 | the root argument is not a usable directory | `deployed-membership: repository root is not a directory: <arg>` |
| 2 | a declared tree is not a directory | `deployed-membership: installed tree is missing: <tree>` |
| 2 | a manifest entry lies under no declared tree | `deployed-membership: manifest entry is outside every declared tree: <entry>` |
| 2 | the enumeration itself fails | `deployed-membership: could not enumerate the installed trees` |

Every finding is reported before the script exits; a run does not stop at the first one.

Exit 1 is a difference the comparison found. Exit 2 is the comparison not happening. That
division is the reason a missing member here is a finding while a missing block site in
`check-shared-standards.sh` is a fault: there the file is an input to a byte comparison that
then cannot run, here its absence is the answer.

### Wiring

```
membership-check:
  ./scripts/check-deployed-membership.sh
```

added to the `verify` dependency list. Not to `commit-check`: that chain is the pre-commit
hook's (record 0039) and holds `lint`, `format-check` and `public-safety`, while every
content gate — `skills-check`, `carrier-check`, `shared-standards-check`,
`references-check` — sits in `verify` alone.

`install.sh` gets one comment at each of the two wholesale call sites naming the manifest, so
a reader adding a third tree learns the gate exists.

## Suite

`scripts/check-deployed-membership-test.sh`, discovered automatically by `just test`, which
globs `*-test.sh` from `git ls-files`. It follows the `check-shared-standards-test.sh` shape:
a `mktemp -d` scratch with a guarded `trap cleanup EXIT`, a `reset_fixture` per case, and
`assert_passes` / `assert_fails` / `assert_exit_two` helpers that pin the message as well as
the status.

The fixture is built by copying the three real trees into the scratch repository, not by
writing synthetic files. A synthetic fixture would have to restate the manifest, so the suite
would assert the checker against a second copy of its own data and would go stale on every
manifest edit. Copying makes the pass case "the repository as it stands agrees with its
manifest" and every other case a delta on top.

| case | expectation |
|---|---|
| the three trees as they are | passes, with the summary line |
| an ordinary file added, once per tree | `unexpected-member` naming it |
| a dot-prefixed file added | `unexpected-member` naming it |
| a file added beside an `.ignore` entry that names it | `unexpected-member` naming it |
| a file added in a new subdirectory | `unexpected-member` naming it |
| a symlink added to an existing member | `unexpected-member` naming it |
| a declared member deleted | `missing-member` naming it |
| a file added outside the declared trees | passes |
| a declared tree removed | exit 2, `installed tree is missing` |
| a second argument | exit 2, `usage:` |
| a root that does not exist | exit 2, `repository root is not a directory` |

The per-tree repetition is deliberate: a gate that enumerated only the first tree would pass
the other two. The `.ignore` and dot-prefix cases pin the enumeration against a later
refactor to `rg`, where they are the two cases that silently narrow the scan.

## Security posture

The change adds no entry point, no secret handling, no dependency, and parses no input it did
not produce, so it does not meet the threat-model trigger. The one boundary worth stating is
the gate's own: its verdict must not be alterable by a file placed in the repository it
checks. `.gitignore`, `.ignore` and `RIPGREP_CONFIG_PATH` are all inputs that can narrow a
ripgrep scan, and `find` reads none of them — that is the control, and the suite's `.ignore`
and dot-prefix cases are its test. The gate reads file names and never file contents.

## Verification

`just verify`, run bare. It reaches the new gate through `membership-check` and the new suite
through `test`.
