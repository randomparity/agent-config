# Skill directory membership — design

Issue: <https://github.com/randomparity/agent-config/issues/124>
Record: [0054](../../adr/0054-the-skills-tree-declares-its-directories.md)
Extends: [0045](../../adr/0045-installed-trees-declare-their-membership.md)

## Problem

`stage_skills` copies `content/skills` with `cp -pR` minus `testdata` entries, and
`install_managed_path` delivers the staged tree to all three agents. A top-level directory added
there ships a complete instruction set into every user's global agent configuration. Nothing
declares the expected set: `check-skill-layout.sh` constrains what a skill must look like and
`scripts/reserved-skill-names.txt` is a forbidden list, not an expected one.

Record 0045 gave three sibling trees a membership gate and booked this as a residual in as many
words. Measured on the branch point: 7 declared files across the three covered trees, against 88
installed files across 36 skill directories with no membership check at all — 96 tracked, of
which `stage_skills` prunes the 8 under `testdata` before delivery.

## Goal

A top-level entry appears under `content/skills` only if a list in
`scripts/check-deployed-membership.sh` declares it, and `just verify` is red until that is true
in both directions.

## Non-goals

- Membership *inside* a skill directory. A file added under `content/skills/<name>/` still
  installs unchecked; the skill directory is the unit of delivery, and the churn argument 0045
  made against a per-file manifest is undisturbed. Containment inside a declared directory —
  a committed `content/skills/<name>/link -> /` — likewise stays `check-skill-layout.sh`'s
  `validate_portable_tree` alone.
- Anything about `examples/project-review-skills/`, a documented non-installed exception
  (record 0020).
- Any change to the three-tree file-granularity rule, its messages, or its emission order.
- Any change to `check-skill-layout.sh`, which keeps sole ownership of skill *shape*.
- Any change to what `install.sh` delivers. Detection only, as in 0045 — its two coupling
  comments are updated, and `stage_skills` gains the pointer for the skills half, because all
  three skill call sites go through it.

## Siting

The rule goes in `scripts/check-deployed-membership.sh`. Record 0054 carries the argument; the
short form is that 0045's shape objection is largely granted — the skills half brings its own
enumerator, filter, sorts, comparisons and finding vocabulary, sharing only the workspace, the
`fault` helper and the collation pin — and the siting rests on two other grounds: that
`check-skill-layout.sh` would mix shape with membership and split the deployment answer across
two scripts, and that 0045's fault-versus-finding exit discipline already lives in the receiving
script and does not exist in the alternative.

No `Justfile` change follows: `membership-check` already runs the script, already sits
immediately after `commit-check` and ahead of every content gate, and that placement is what
this rule wants too — `skills-check` faults on a missing `content/languages` or
`content/references` root, so a later placement could leave the membership answer unprinted.

## The rule

### Data

One further literal beside the existing two, for the same reason 0045 kept those inline — it
means nothing apart from the comparison that consumes it:

- `skills_tree`, the repo-relative tree: `content/skills`;
- `skill_directories`, a newline-delimited list of the 36 top-level directory names, bare rather
  than repo-relative, because the prefix is fixed and repeating it 36 times invites a typo the
  comparison would report as a missing directory beside an unexpected one.

Two comment blocks in the same file assert the opposite of the new rule and are edited with it,
because nothing gates a script comment's accuracy: the `trees` preamble, which says
`content/skills` "is deliberately absent" and cites 0045 for it, and the file header, which
scopes the whole script to three trees and to the residual 0041 disclosed.

### Enumeration

The tree survives the same `-d` **and not** `-L` filter the three trees get, and for the same
reason: `test -d` dereferences, so a `content/skills` replaced by a symlink to a directory would
otherwise be walked and its target's children declared members of this repository's tree. A tree
that does not survive contributes no entries, so all 36 declared names report as missing. That
is 0045's no-fault-for-a-missing-tree decision applied unchanged, and it is why the enumeration
is guarded by the filter rather than by a fault.

Surviving, the top-level children are enumerated with
`find "$ROOT/content/skills" -mindepth 1 -maxdepth 1 -print0`. The root is excluded by depth,
which deviates deliberately from `validate_inventory`'s `! -path "$root"` form and from the
`! -name .` variant of it. Both of those exclude the root by matching a pattern against it, and
both have a case where the match fails and the root is printed as an entry with none of its
children — the gate then emits `unexpected-skill-entry` for the tree itself beside all 36
declared names as missing, a total false red. `-path` matches by fnmatch, so a repository root
holding a well-formed bracket expression or a backslash does not match itself (verified: a root
`br[ab]d/content/skills` enumerates the root and no children; an *unterminated* `[`, or a `*` or
`?`, does self-match, since each also matches its own literal character). `! -name .` fails the
other way and on a platform this repository actually gates: BSD `find` sets a start point's
`fts_name` to the whole operand string rather than its basename, so `-name .` is false at the
root, `-prune` fires there, and the macOS leg gets the same false red. Depth compares no
patterns at all. `-mindepth`/`-maxdepth` are not POSIX but are carried by GNU find, BSD find and
bfs alike, and `check-skill-layout-test.sh:288` already runs `-maxdepth 1` on the `macos-latest`
leg. This is the one place the script's rule that the environment must not reach the verdict has
a path-shaped input; the three-tree half is immune because it passes its operands to `find`
directly and never pattern-matches them.

`find` is used rather than the repository's usual `rg` for 0045's reason, which is stronger here
than there: `cp -pR` ships dot-prefixed and gitignored entries, ripgrep applies `.gitignore` to
tracked files too, and `find` reads no ignore file and no `RIPGREP_CONFIG_PATH`, so there is no
flag for a later edit to drop.

The status is captured directly rather than through a pipeline, so a scan that did not happen
cannot read as an empty one; failure is `fault 'could not enumerate the skills tree'`, exit 2.

Every enumerated child is a member of the present set **whatever its type** — a regular file, a
symlink, a fifo. The comparison is over names, so a stray `content/skills/README.md` is an
undeclared entry and reports as one, which is both true and the answer a reader needs.

**An entry that is not a directory, or is a symlink, is additionally a finding whatever the list
says.** This is 0045's `non-regular-member` rule at this granularity, and the argument is the
one 0045 gives: `cp -pR` preserves a symlink and `find -prune` does not descend one, so a
declared name resolving to a link would deploy whatever its target resolves to on the user's
machine — an unbounded subtree admitted by one declaration. The two rules compose as they do
for files: a non-directory entry **is** a member for the set comparison, so a declared one
reports `non-directory-skill-entry` alone and never `missing-skill-directory`, while an
undeclared one reports `unexpected-skill-entry` and `non-directory-skill-entry` both.

`check-skill-layout.sh` refuses the same entries — `validate_portable_tree` forbids a symlink
anywhere under the tree and `validate_inventory` requires every child to be a real directory.
The overlap is what record 0054's containment line costs: a symlink makes the declaration itself
unbounded, so this gate has to hold that on its own, while the `SKILL.md` every child must carry
stays `validate_inventory`'s rule alone because a directory lacking it is malformed rather than
unbounded.

### Comparison

Names are compared, not paths. A name holding a newline cannot be represented in a
line-delimited comparison and is refused with `fault`, exit 2, before any comparison — 0045's
reasoning transfers exactly: two halves that both equal declared names would collapse under
`sort -u` and leave the gate green over a directory `cp -pR` ships. The name is not echoed,
because a newline in a diagnostic is how it would be misread again.

Both sides go through `sort -u` and the two difference sets are taken with `comm`, each call
routed to `fault` on failure so that a full disk or a broken tool cannot borrow exit 1. The
`export LC_ALL=C` at the top of the script already pins the collation for `sort`, `comm` and the
emission order, and covers these calls unchanged.

The non-directory list goes through `sort -u` as well. It is built by walking `find -print0`
output, which returns readdir order, so without its own sort its block would emit in whatever
order the filesystem gave — the one class whose ordering nothing else pins.

`sort -u` makes a duplicated list line inert, as it does for the file manifest.

### Verdicts

| status | condition | message |
|---|---|---|
| 1 | present, not declared | `deployed-membership: unexpected-skill-entry: content/skills/<name>` |
| 1 | present, not a directory | `deployed-membership: non-directory-skill-entry: content/skills/<name>` |
| 1 | declared, not present | `deployed-membership: missing-skill-directory: content/skills/<name>` |
| 2 | a skill directory name contains a newline | `deployed-membership: a skill directory name contains a newline and cannot be compared` |
| 2 | the enumeration fails on a surviving tree | `deployed-membership: could not enumerate the skills tree` |
| 2 | a skills-half workspace write fails | `deployed-membership: could not write to the workspace` |
| 2 | a skills-half `sort` fails | `deployed-membership: could not sort the enumerated skill directories` |
| 2 | a skills-half `comm` fails | `deployed-membership: could not compare the enumerated skill directories against the declared set` |

The last two are deliberately not the three-tree half's strings. `could not sort the enumerated
members` and `could not compare the enumerated members against the manifest` both name the file
manifest, and reusing them would leave an operator unable to tell which half faulted — which is
also what makes the suite row below able to assert the half it landed in.

The vocabulary is deliberately split between `entry` and `directory`. A present child's type is
not known to be a directory — that is what one of the classes is for — so the two present-side
classes say `entry`. A declared name that is absent is by construction a missing skill
*directory*, since a directory is the only thing the list may declare.

`unexpected-skill-entry` carries the same two-opposite-remedies hazard `unexpected-member` does,
so it gets its own remedy line, emitted once after the skills block when that class fired:
`deployed-membership: delete an unexpected entry, or declare it here only if it is a skill meant
to install for every user`. A separate line rather than the existing one: the existing text says
"member", the two blocks can fire independently, and a reader given one remedy for a finding in
the other block has to work out which it addresses.

### Emission order

Unchanged for the three trees, then the skills block:

The internal sequence is pinned too, and not only the emission: the three trees' enumeration,
sorts and comparisons run first, then the skills half's, then all emission. Without that, a
suite row keyed to a mocked tool's invocation index cannot say which half it lands in.

1. `unexpected-member`, `non-regular-member`, `missing-member` — each in `LC_ALL=C` order;
2. the existing remedy line, when `unexpected-member` fired;
3. `unexpected-skill-entry`, `non-directory-skill-entry`, `missing-skill-directory` — each in
   `LC_ALL=C` order;
4. the skills remedy line, when `unexpected-skill-entry` fired.

Putting the whole skills block after the existing remedy line, rather than interleaving the two
rules' classes, is what keeps every `assert_findings` sequence in the existing suite asserting
the same bytes it asserts today. That is the executable form of "the existing behavior is
unchanged".

All enumeration and both comparisons complete before any finding is emitted, preserving 0045's
invariant that a fault can never suppress a finding already made or emit a partial set. That
ordering is global, and the consequence is worth stating rather than discovering: a skills-side
fault — an unreadable tree, a name holding a newline, a workspace write that fails — now
withholds the three-tree findings of the same run, which today would print. The run exits 2 and
says why, so nothing is lost silently, but the operator gets one answer instead of two. Record
0054 carries it in its residual list, and a suite row pins it.

### Summary

```
deployed-membership: ok (<n> declared members across <m> installed trees, <k> declared skill directories in content/skills)
```

`<k>` is the number of distinct declared names, so a duplicated list line does not inflate it.
The summary states both granularities because the script now answers at two, and a reader who
saw only `<n>` would take it for the whole deployment. The clause names the tree because
`content/skills` is a fourth installed tree the same gate now covers, and without the name a
reader has to infer that the 36 directories are not among the `<m>`. `<m>` stays the count of
*surviving* file-granularity trees and the skills tree is deliberately not folded into it: the
two numbers mean different things — `<m>` drops when a tree is absent, `<k>` never does — and
the suite pins `<m>` against the three trees it lists.

## Suite

`scripts/check-deployed-membership-test.sh` gains the skills tree to its fixture and a block of
rows. The fixture keeps being checked out of the **index** for 0045's reasons — a synthetic one
would restate the declared list, and a working-tree copy would drag in the gate's own accepted
false positive. `content/skills` joins the `ls-files -z | checkout-index` build and the
unmerged-path guard; `TREES` stays the three, because `EXPECTED_MEMBERS` is the file-granularity
count and must not absorb 96 skill files.

`EXPECTED_SKILL_DIRECTORIES` is enumerated from the same index listing rather than pinned as a
literal, for the reason the member count is: pinning 36 would be the second copy of the declared
list the fixture design exists to avoid, and would make adding a skill three edits with the
third arriving as a red suite.

| case | expectation |
|---|---|
| the tree as tracked | passes; whole summary line asserted, including `<k>` against the enumerated directory count |
| a new undeclared directory | `unexpected-skill-entry` naming it, exit 1 |
| a dot-prefixed undeclared directory | `unexpected-skill-entry` naming it |
| an undeclared directory named by an `.ignore` at the fixture root | `unexpected-skill-entry` naming it |
| a declared directory removed | `missing-skill-directory` naming it |
| a stray regular file at the top level | `unexpected-skill-entry` **and** `non-directory-skill-entry`, then the skills remedy |
| a declared directory replaced by a symlink to a directory | `non-directory-skill-entry` alone; `missing-skill-directory` asserted absent |
| two undeclared directories | both lines in `LC_ALL=C` order, proving the run does not stop at the first |
| one undeclared and one removed in a single run | both lines, unexpected before missing |
| a file added *inside* a declared skill directory | passes — the residual, asserted rather than assumed |
| a directory name containing a newline | exit 2, `a skill directory name contains a newline` |
| the whole `content/skills` tree removed | all `<k>` declared names as `missing-skill-directory`, and nothing else |
| `content/skills` replaced by a symlink to a directory | all declared names missing; no entry from behind the link |
| the skills tree made unreadable | exit 2, `could not enumerate the skills tree`, with no `missing-skill-directory` line; skipped as root, announcing the skip |
| a three-tree finding and a skills finding in one run | the file block, its remedy, then the skills block, then its remedy — the ordering guarantee |
| a `comm` that fails only on the skills-half comparison | exit 2 and the skills-half comparison message exactly. The existing mock exits 1 unconditionally and so faults inside the three-tree half, leaving the skills-half routing unasserted; this one counts invocations and fails the third, which the pinned internal sequence makes well-defined, and asserting the distinct string is what fails the row if it lands in the wrong half |
| two stray top-level files beside a declared directory removed | `unexpected-skill-entry` twice, `non-directory-skill-entry` twice, then `missing-skill-directory`, then the skills remedy — the skills-half counterpart of the file half's multiplicity-and-inter-block row, and the only place the non-directory class's ordering and multiplicity are pinned |
| a three-tree finding beside an unreadable `content/skills` | exit 2, no `unexpected-member` line — pins the global ordering consequence above; skipped as root |
| a fixture root holding a well-formed bracket expression | passes, with the same summary. Reddens under either pattern-matching form: `! -path` fails to self-match a bracket root, so the row is a form-pin and not merely a hostile-path case |

Every existing row is re-run unchanged except where the summary is pinned in full, which is two
edit sites covering four rows: the `assert_passes` helper's expected string, which three rows
call, and the inline `POSIXLY_CORRECT` comparison. Both gain the `<k>` clause and stay
exact-match rather than being relaxed to a substring. That is the evidence for the
no-regression criterion.
Two of them are re-read rather than merely re-run: the `.ignore` and dot-prefix rows for the
three trees, and the `missing-member` rows, are the behaviors the issue names as
must-not-regress, and their expected sequences are unchanged bytes.

The `assert_findings` helper already compares whole stderr sequences in order, so the block
ordering above is asserted rather than described. `assert_fails` and `assert_absent` cover the
single-finding and must-not-appear rows. Every finding row requires exactly exit 1.

## Security posture

No entry point, no secret, no dependency, no input the change did not produce; the
threat-model trigger is not met. Two boundaries carry over from 0045 and are worth restating
because this change widens the surface they cover:

- *The gate's verdict must not be alterable by a file placed in the repository it checks.*
  `.gitignore`, `.ignore` and `RIPGREP_CONFIG_PATH` all narrow a ripgrep scan; `find` reads none
  of them. The `.ignore` and dot-prefix rows are the test.
- *A declaration must not admit an unbounded subtree.* A committed symlink resolves on the
  user's machine at read time, so one declared name could otherwise deploy an arbitrary tree,
  including one reached by a `../`-relative path out of the configuration directory. Refusing
  every non-directory entry is the control and it cannot be waived by declaring the name.

## Sequencing

The comment edits in `install.sh` and in the gate script describe a rule, so they land in or
after the commit that adds it. A commit that documents a gate the branch does not yet carry
reads as reassurance and is harder to notice than a missing gate.

## Verification

`just verify`, run bare, plus `BASE_SHA=$(git merge-base HEAD origin/main) just records` for the
append-only record gate, which `just verify` does not exercise locally.
