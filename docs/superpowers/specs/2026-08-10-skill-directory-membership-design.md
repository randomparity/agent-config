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
words. Measured on the branch point: 7 declared files across the three covered trees, 96 tracked
files across 36 skill directories with no membership check at all.

## Goal

A top-level entry appears under `content/skills` only if a list in
`scripts/check-deployed-membership.sh` declares it, and `just verify` is red until that is true
in both directions.

## Non-goals

- Membership *inside* a skill directory. A file added under `content/skills/<name>/` still
  installs unchecked; the skill directory is the unit of delivery, and the churn argument 0045
  made against a per-file manifest is undisturbed.
- Anything about `examples/project-review-skills/`, a documented non-installed exception
  (record 0020).
- Any change to the three-tree file-granularity rule, its messages, or its emission order.
- Any change to `check-skill-layout.sh`, which keeps sole ownership of skill *shape*.
- Any change to what `install.sh` delivers. Detection only, as in 0045.

## Siting

The rule goes in `scripts/check-deployed-membership.sh`. Record 0054 carries the argument and
answers 0045's shape objection; the short form is that one comparison rule gains a second
enumerator rather than the script gaining a second rule, that `check-skill-layout.sh` would mix
shape with membership and split the deployment answer across two scripts, and that 0045's
fault-versus-finding exit discipline already lives in the receiving script and does not exist in
the alternative.

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

### Enumeration

The tree survives the same `-d` **and not** `-L` filter the three trees get, and for the same
reason: `test -d` dereferences, so a `content/skills` replaced by a symlink to a directory would
otherwise be walked and its target's children declared members of this repository's tree. A tree
that does not survive contributes no entries, so all 36 declared names report as missing. That
is 0045's no-fault-for-a-missing-tree decision applied unchanged, and it is why the enumeration
is guarded by the filter rather than by a fault.

Surviving, the top-level children are enumerated with
`find "$ROOT/content/skills" ! -path "$ROOT/content/skills" -prune -print0` — the idiom
`check-skill-layout.sh`'s `validate_inventory` already uses. `find` is used rather than the
repository's usual `rg` for 0045's reason, which is stronger here than there: `cp -pR` ships
dot-prefixed and gitignored entries, ripgrep applies `.gitignore` to tracked files too, and
`find` reads no ignore file and no `RIPGREP_CONFIG_PATH`, so there is no flag for a later edit
to drop.

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
The overlap is deliberate: a membership verdict that is only correct while a sibling gate stays
red is not a verdict this script can make, and 0045 already accepts the same overlap for
`non-regular-member`.

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

`sort -u` makes a duplicated list line inert, as it does for the file manifest.

### Verdicts

| status | condition | message |
|---|---|---|
| 1 | present, not declared | `deployed-membership: unexpected-skill-entry: content/skills/<name>` |
| 1 | present, not a directory | `deployed-membership: non-directory-skill-entry: content/skills/<name>` |
| 1 | declared, not present | `deployed-membership: missing-skill-directory: content/skills/<name>` |
| 2 | a skill directory name contains a newline | `deployed-membership: a skill directory name contains a newline and cannot be compared` |
| 2 | the enumeration fails on a surviving tree | `deployed-membership: could not enumerate the skills tree` |

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
invariant that a fault can never suppress a finding already made or emit a partial set.

### Summary

```
deployed-membership: ok (<n> declared members across <m> installed trees, <k> declared skill directories)
```

`<k>` is the number of distinct declared names, so a duplicated list line does not inflate it.
The summary states both granularities because the script now answers at two, and a reader who
saw only `<n>` would take it for the whole deployment.

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

The existing rows are re-run unchanged, which is the evidence for the no-regression criterion.
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

## Verification

`just verify`, run bare, plus `BASE_SHA=$(git merge-base HEAD origin/main) just records` for the
append-only record gate, which `just verify` does not exercise locally.
