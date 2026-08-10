# Installed tree membership — design

Issue: <https://github.com/randomparity/agent-config/issues/106>
Record: [0045](../../adr/0045-installed-trees-declare-their-membership.md)

## Problem

`install_managed_path` ends in `cp -pR`. When its source is a directory the whole subtree
lands in the agent's configuration directory. Four directory sources reach it, across six
call sites — the staged skills tree is passed once per agent:

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

`content/skills` stays out of this design, on the grounds recorded in 0045: its unit of
delivery is the skill directory rather than the file, and `check-skill-layout.sh` gates that
unit at its boundary — every top-level child must be a skill directory with a valid
`SKILL.md`, and a whole-tree walk forbids symlinks and non-regular files and constrains every
path component. What it never does is declare an expected set — so both a file added inside a
skill directory and a whole new top-level skill directory still deploy unchecked. Those
residuals are recorded, not closed, and the directory-level half has its own issue. The cost
side of a per-file manifest is the other consideration: 96 files across eleven commits there,
against seven files and one commit in the three covered trees.

## Goal

A file appears in `agents/bob/shared/rules`, `content/languages` or `content/references` only
if a manifest declares it, and `just verify` is red until that is true in both directions.

## Non-goals

- Changing what `install.sh` deploys, or how. This adds detection only.
- Gating `content/skills` membership, or the contents of any listed file.
- Detecting a *new* wholesale-installed tree added to `install.sh` and not to the manifest. A
  comment at each call site is the coupling; making it detectable is its own design decision
  and has its own issue.

## The gate

`scripts/check-deployed-membership.sh [repository-root]`, message prefix
`deployed-membership:`. The optional argument names a repository root to check instead of the
script's own, which is how the suite points it at a fixture — the same contract
`check-shared-standards.sh` and `check-deployed-references.sh` offer.

### Data

Two literals in the script — inline rather than in a data file beside it, following
`check-shared-standards.sh`, because the lists are short and mean nothing apart from the
comparison that consumes them:

- the declared trees, repo-relative: `agents/bob/shared/rules`, `content/languages`,
  `content/references`;
- the manifest, a newline-delimited list of repo-relative paths, one per declared member.

At the time of writing the manifest holds seven entries: the one rules file, five language
references, and one orchestration reference.

### Enumeration

The tree list is filtered to real directories — `-d` **and not** `-L` — before anything else,
so only surviving directories reach `find`. `-d` alone would be wrong: `test -d` dereferences,
so a tree replaced by a symlink to a directory would survive it, and `find` would then print
the tree path itself as a non-directory entry. Tree paths are passed to `find` without a
trailing slash, since a trailing slash forces `find` to dereference the argument and changes
the answer. A declared tree that is absent, or present as a regular file or as a symlink,
contributes no members, and its declared files therefore report as `missing-member`.

Every entry under a surviving tree that is not a directory is a member: regular files,
symlinks, and dot-prefixed and ignored files alike, because `cp -pR` copies all of them.
`find <trees> ! -type d -print0` produces exactly that set and has no ignore logic to defeat,
which is why it is used here in place of the repository's usual `rg`.

**A member that is not a regular file is additionally a finding, whatever the manifest says.**
`cp -pR` preserves a symlink rather than dereferencing it, and `find ! -type d` does not
descend one, so a symlink to a directory would enumerate as a single path while deploying
whatever its target resolves to on the user's machine — an unbounded subtree admitted by one
manifest line, including paths outside the configuration directory if the committed link text
is `../`-relative. Declaring it must not make it acceptable. This follows
`check-skill-layout.sh`, which refuses symlinks and non-regular files anywhere under the
skills tree.

The two rules compose as follows, and the suite pins each half. A non-regular entry **is** a
member for the set comparison, so a declared symlink never reports `missing-member` — the file
is there, it is just not allowed to be what it is. The regular-file check is an independent
report over the same enumerated set. So a declared non-regular entry emits one line
(`non-regular-member`) and an undeclared one emits two (`unexpected-member` and
`non-regular-member`), each true on its own terms.

The ignored case is reachable where it counts, not only in a dirty working tree: ripgrep
applies `.gitignore` to *tracked* files too, so a tracked file the repository also ignores is
shipped by `cp -pR` and skipped by a default ripgrep scan, in CI as much as locally. The cost
of reading no ignore rules is that untracked local debris under one of the three trees turns
a local `just verify` red — neither `verify-push.sh`, which rehearses in a detached worktree
of the pushed objects, nor CI on a clean checkout sees it.

### Comparison and verdicts

Both sides are read into Bash associative arrays keyed by repo-relative path — `declared` from
the manifest, `present` from the NUL-delimited enumeration — and each is then tested for
membership of the other. Keying makes a manifest line duplicated by a careless edit inert by
construction rather than by promise: a repeated key is the same key. `comm` was the obvious
alternative and does not hold that property — `comm -23` emits the surplus occurrence of a
duplicated entry as file1-only, which is exactly a spurious `missing-member` for a file that
is plainly there — and it has no NUL mode, so it does not compose with the enumeration either.
Like the tree-containment rule, the duplicate property is not fixture-reachable, because the
manifest is a literal in the script; it holds structurally or not at all.

The enumeration completes before any comparison begins, so an enumeration fault (exit 2) is
reached while no finding yet exists. A fault therefore never suppresses findings that were
already made, and never emits partial ones.

| status | condition | message |
|---|---|---|
| 0 | the two sets are equal | `deployed-membership: ok (<n> declared members across <m> installed trees)` |
| 1 | present, not declared | `deployed-membership: unexpected-member: <repo-relative path>` |
| 1 | declared, not present | `deployed-membership: missing-member: <repo-relative path>` |
| 1 | present, not a regular file | `deployed-membership: non-regular-member: <repo-relative path>` |
| 2 | more than one argument | `usage: check-deployed-membership.sh [repository-root]` |
| 2 | the root argument is not a usable directory | `deployed-membership: repository root is not a directory: <arg>` |
| 2 | the enumeration itself fails | `deployed-membership: could not enumerate the installed trees` |

Findings and faults go to stderr, the `ok` summary to stdout, matching
`check-shared-standards.sh`. The suite captures the two streams separately rather than merging
them as `check-shared-standards-test.sh` does, so this is an assertion and not a description.

A run reports every finding before it exits; it does not stop at the first. This matters in
the intended use — a wave branch that adds one file and deletes another must be told about
both, not sent round the loop twice. Emission order is fixed so the suite can assert it: all
`unexpected-member` lines, then all `non-regular-member` lines, then all `missing-member`
lines, each in `LC_ALL=C` path order.

A declared tree that is not a directory is deliberately **not** a fault. It contributes no
members, so every file the manifest declares under it reports as `missing-member`. That case
is reachable: `agents/bob/shared/rules` and `content/references` hold one file each, Git does
not track empty directories, and so the commit deleting that file removes the directory from
every fresh checkout. A fault there would report the gate as unable to run, about the deletion
it exists to describe. Since the `-d` filter runs first, a missing tree can never make the
enumeration fail; the exit-2 enumeration fault is left for a real failure, such as an
unreadable directory.

There is deliberately no fault for a manifest entry lying under no declared tree. Both lists
are literals in the same script, so no repository state can trigger it — it would be a lint on
source that no fixture could exercise — and such an entry already reports as `missing-member`,
which is loud and correct. Containment is still defined where it is used: an entry belongs to
a tree when it begins with `<tree>/`, so `content/languages-archive/x.md` does not belong to
`content/languages`.

Exit 1 is a difference the comparison found. Exit 2 is an input the gate cannot make sense of
at all. This is where the gate parts company with `check-shared-standards.sh` and
`check-deployed-references.sh`, which both fault on a missing scan root: neither compares
membership, so for neither is the root's absence itself an answer.

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
globs `*-test.sh` from `git ls-files`. It follows the `check-shared-standards-test.sh` shape —
a `mktemp -d` scratch with a guarded `trap cleanup EXIT`, a `reset_fixture` per case, and
`assert_passes` / `assert_fails` / `assert_exit_two` helpers that pin the message as well as
the status — with two deliberate departures, each because a guarantee here would otherwise be
unfalsifiable:

- `run_checker` captures stdout and stderr into separate files instead of merging them, so the
  stream split is asserted rather than described.
- an `assert_findings` helper compares the whole stderr finding sequence against an expected
  list in order, so multiplicity and emission order can fail. `assert_fails` remains for the
  single-finding rows, and `assert_absent` (also from the sibling suite) pins the lines a case
  must *not* produce.

The fixture is populated from the **tracked** contents of the three trees — the paths
`git ls-files -z` reports, copied from the working tree — rather than from synthetic files or
a plain directory copy. A synthetic fixture would have to restate the manifest, so the suite
would assert the checker against a second copy of its own data and go stale on every manifest
edit. A plain working-tree copy would drag in the gate's own accepted false positive: untracked
debris under a covered tree would make the fixture disagree with the manifest before any case
ran, so every case would fail for a reason unrelated to what it tests, and the suite's result
would depend on the developer's untracked files. Reading the tracked set keeps the fixture
derived from the repository and deterministic. The consequence to know: a new deployed file
must be staged before the suite sees it, so adding one and its manifest line without
`git add` shows up here as a `missing-member` on the pass case.

The same reasoning governs the pass case's summary. Pinning a literal `7 declared members`
would be the second copy of the manifest this fixture design exists to avoid, and it would make
adding a deployed file three edits rather than the two ADR 0045 promises — with the third
arriving as a red suite, which reads as a broken test rather than as the gate working. So the
suite asserts the summary against the count it enumerated when building the fixture, and
separately asserts that count is non-zero, which is what keeps an emptied manifest from passing
vacuously with `0 declared members`.

| case | expectation |
|---|---|
| the three trees as tracked | passes; summary asserted against the count the suite itself enumerated, and asserted non-zero, on stdout |
| an ordinary file added, once per tree | `unexpected-member` naming it |
| a dot-prefixed file added | `unexpected-member` naming it |
| a file added beside an `.ignore` entry that names it | `unexpected-member` naming it |
| a file added in a new subdirectory | `unexpected-member` naming it |
| an undeclared symlink to an existing member | `unexpected-member` **and** `non-regular-member`, in that order |
| an undeclared symlink to a directory | `unexpected-member` **and** `non-regular-member`; no member from behind the link |
| a declared member replaced by a symlink to it | `non-regular-member` alone; `missing-member` asserted absent |
| a declared member deleted | `missing-member` naming it |
| two undeclared files under one tree | both `unexpected-member` lines, in `LC_ALL=C` path order |
| an undeclared file under one tree **and** a declared member deleted under another | both lines in one run, unexpected before missing |
| a file added outside the declared trees | passes |
| a one-file declared tree removed entirely | `missing-member` naming its declared file, not a fault |
| a one-file declared tree replaced by a regular file | `missing-member` naming its declared file, not a fault |
| a one-file declared tree replaced by a symlink to a directory | `missing-member` naming its declared file, not a fault; the tree path itself is not reported |
| a declared tree made unreadable | exit 2, `could not enumerate`, with no `missing-member` line for that tree; skipped when the suite runs as root |
| a second argument | exit 2, `usage:` |
| a root that does not exist | exit 2, `repository root is not a directory` |

Several of these exist to defeat a specific shortcut. The per-tree repetition catches a gate
that enumerated only the first tree. The `.ignore` and dot-prefix cases pin the enumeration
against a later refactor to `rg`, where they are the two cases that silently narrow the scan.
The two-delta case catches a checker that reports the first disagreement and exits, which
every single-delta case above would otherwise accept. The unreadable-tree case catches a
checker that lets a `find` failure fall through as an empty enumeration — which would report
every declared file as missing and pass a suite without it, the fault class swallowing a
finding in the direction the record forbids.

## Security posture

The change adds no entry point, no secret handling, no dependency, and parses no input it did
not produce, so it does not meet the threat-model trigger. The one boundary worth stating is
the gate's own: its verdict must not be alterable by a file placed in the repository it
checks. `.gitignore`, `.ignore` and `RIPGREP_CONFIG_PATH` are all inputs that can narrow a
ripgrep scan, and `find` reads none of them — that is the control, and the suite's `.ignore`
and dot-prefix cases are its test. The gate reads file names and never file contents.

The second boundary is what a declared member may be. A symlink is committed source whose
target resolves on the user's machine at read time, so admitting one by manifest line would
let a single declaration deploy an arbitrary subtree, including one reached by a `../`-relative
path out of the configuration directory. Refusing every non-regular member is the control, and
it cannot be waived by declaring the path.

## Verification

`just verify`, run bare. It reaches the new gate through `membership-check` and the new suite
through `test`.
