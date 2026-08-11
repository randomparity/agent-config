# 0054 — The skills tree declares its directories

## Status

Accepted (2026-08-10)

## Context

Record 0045 gave three wholesale-installed trees a membership gate and left `content/skills`
out of it. The exclusion was a cost argument: `stage_skills` copies that tree with `cp -pR`
minus `testdata`, so its files are deployed content too, but a per-file manifest over 96 files
would churn on ordinary work — eleven adding commits there against one across the three covered
trees at the time, and 132 commits touching `content/skills` in the last 90 days against 6 for
the three gated trees combined.

0045 recorded the resulting hole in its own Consequences: "a whole new top-level skill directory
[installs to every user] with no membership check". `check-skill-layout.sh` constrains what a
skill must *look* like — portable-ASCII paths, a valid `SKILL.md`, no symlinks, no reserved name
— and `scripts/reserved-skill-names.txt` is a forbidden list rather than an expected one.
Nothing declares which skills exist. The gate as merged covers 7 of the 103 installed content
files; the 96 it does not cover sit in 36 skill directories, any number of which could become 37
in a merge nobody read closely.

The churn objection does not reach directory granularity, and 0045 said so when it listed the
alternative it was rejecting: `git log --diff-filter=A -- 'content/skills/*/SKILL.md'` names
exactly two commits that ever introduced a top-level skill directory. 0045 rejected that
alternative on **shape**, not cost — "this gate compares one flat set of files, and a tree
compared at a different granularity puts two comparison rules in one script.
`check-skill-layout.sh` already enumerates those children and is the natural home."

## Decision

**The skills tree is declared in `scripts/check-deployed-membership.sh`, beside the three
file-granularity trees, as a second declared list compared by the same rule at directory
granularity.** Record 0045's siting objection is answered rather than accepted, on three
grounds.

*The objection counts rules where there is one.* The gate asserts set equality between what a
wholesale-installed tree contains and what a list declares. That rule is unchanged; only the
enumerator differs — `find <trees> ! -type d` for the three file-granularity trees, and the
top-level children not descended into (`find "$root" ! -path "$root" -prune`, the idiom
`validate_inventory` uses, over the `$ROOT`-absolute path this script builds for every tree) for
the one whose unit of delivery is the directory. Two enumerators feeding one comparison is not
two comparison rules.

*The alternative siting mixes two subjects.* `check-skill-layout.sh` answers "is each skill
well-formed"; membership answers "which skills exist". Split that way, a reader asking what the
repository installs for every user reads two scripts and gets half the answer from each, with
neither summary stating the whole.

*The receiving script's discipline is what a membership comparison needs, and the alternative
does not have it.* 0045's exit-code split — exit 1 for a difference found, exit 2 for input the
gate cannot make sense of, never the reverse — is load-bearing, because a membership answer an
unwritable `TMPDIR` can forge is not an answer; the receiving script routes every `mktemp`,
`sort`, `comm` and truncation through a `fault` helper for that reason. `check-skill-layout.sh`
exits 1 from `skill_error` for every condition it names, a missing `reserved-skill-names.txt`
included, so siting membership there means importing that discipline or accepting a rule whose
environmental failures read as findings.

**The declared unit is the directory name, not the directory plus its required file.**
`content/skills/<name>/SKILL.md` is already required of every top-level child by
`check-skill-layout.sh`'s `validate_inventory`. The line between what this gate re-checks and
what it leaves to that one is **containment, not duplication**: a declared name resolving to a
symlink makes the declaration itself dishonest, because one line then admits whatever the target
resolves to on the user's machine, whereas a declared directory with no `SKILL.md` leaves the
declaration accurate and only the skill malformed.

**So present entries are compared by name whatever their type, and an entry that is not a
directory is additionally a finding.** That is 0045's `non-regular-member` rule at the other
granularity and for its reason: `cp -pR` preserves a symlink and `find -prune` does not descend
one. `check-skill-layout.sh` refuses such an entry too, and the overlap is what the containment
rule costs to hold here on its own.

**The three-tree block emits first, followed by the skills block.** The three trees' finding
classes, remedy line and emission order are unchanged, so 0045's suite rows that pin a whole
finding sequence keep asserting the same bytes. The summary gains one clause naming the declared
directory count, so every row that pins the summary in full — the pass rows — has that expected
string edited once, and the suite derives the directory count from the fixture it builds, the
way it already derives the member count, rather than pinning a literal.

## Consequences

- Adding a skill is now two edits: the directory, and the line in this gate that admits it.
  Removing one is likewise two. At two adding commits in the repository's history that is a cost
  the churn objection cannot reach, but it is not zero — a wave that adds a skill on one branch
  turns a sibling branch red after it merges, and the remedy is the one-line edit.
- A whole new skill directory can no longer deploy to every user unread. That is the specific
  hole 0045 booked and this record closes.
- **What remains uncovered, stated rather than implied away:**
  - *Membership inside a skill directory.* A file added under an existing
    `content/skills/<name>/` — an asset, a carrier, a second Markdown file — still installs with
    no membership check. This is the residual the issue books deliberately, and it is the larger
    half by file count: 96 files sit inside the 36 declared directories. `check-skill-layout.sh`
    constrains what those files may be named, contain and reference; nothing counts them.
  - *The manifest is source, so the gate cannot defend against edits to itself.* Deleting a
    declared name while the directory is there makes the directory undeclared, which is red.
    Deleting a name and its directory together is green, and correctly so — that is a removal.
    What survives is a coordinated edit to this script's lists and the suite's, exactly as 0045
    records for the file-granularity half.
  - *Nothing couples the declaration to `install.sh`.* A fifth wholesale-installed tree added to
    the installer is uncovered until someone adds it here, and no gate detects the omission.
    0045 records this and it is unchanged.
  - *Directory names only.* The gate says nothing about whether a declared skill should ship, or
    what it contains.
  - *The sibling gate this record argues from is itself undisciplined.* `check-skill-layout.sh`
    exits 1 for every condition it names, including a missing `reserved-skill-names.txt` and an
    unwritable scan sink, so a fault there is indistinguishable from a finding. The siting
    argument above leans on that and does not fix it — the sibling gates were outside this
    change. Issue #158 owns it.
- The repository now has two answers to "what installs for every user" in one script and at two
  granularities. A reader has to know which tree they are asking about; the summary line names
  both counts so the split is visible rather than inferred.
- `examples/project-review-skills/` is untouched — it is a documented non-installed exception
  (record 0020) and gating it as installed would be wrong. `check-skill-layout.sh` continues to
  be the only gate that reads it.

## Considered & rejected

- **Put the declaration in `check-skill-layout.sh`, as 0045 proposed.** The closest thing to a
  settled position, and the issue names it too. Rejected on the three grounds in the Decision,
  plus one they do not cover: every fixture in `check-skill-layout-test.sh` builds a one-skill
  tree and would have to carry a declaration matching it, so the rule's cost lands on 60-odd
  existing cases that are about something else.
- **Declare `content/skills/*/SKILL.md` as ordinary file members instead of declaring
  directories.** The smallest alternative available — no second granularity, no new member
  class, and the existing `non-regular-member` rule covers a symlinked `SKILL.md` unchanged.
  Rejected because it does not answer the question asked. The bijection with the directory set
  holds only while `validate_inventory` stays red on a child lacking that file, so a directory
  shipped with an `assets/` payload and no `SKILL.md` is invisible to this enumeration while
  `cp -pR` deploys it — the acceptance criterion is that a new undeclared *directory* fails
  *this* gate. It needs a second enumerator regardless: adding `content/skills` to the existing
  tree list enumerates all 96 files, not the 36.
- **Declare directories *and* their `SKILL.md`.** Rejected on the containment line in the
  Decision: the required file is `validate_inventory`'s rule with its own cases, and a declared
  directory missing it is malformed rather than unbounded.
- **Declare the 96 files inside the directories as well.** Rejected on the cost argument 0045
  made and this record does not disturb: 132 commits touched `content/skills` in the last 90
  days, and a per-file manifest would make most of them two-part edits. Recorded above as the
  standing residual rather than closed.
- **A separate `scripts/expected-skill-names.txt`, mirroring `reserved-skill-names.txt`.**
  Rejected: 0045 put its manifest inline because it means nothing apart from the comparison that
  consumes it, and that is as true of 36 names as of 7. A data file would also need its own
  parse rules, its own malformed-entry class, and its own fault path for being unreadable — new
  failure modes bought for a line count.
- **Derive the expected set from `git ls-files`, or from the tree.** Rejected for 0045's reason,
  which is the whole point of a manifest: a list derived from what is there agrees with whatever
  is there, so it passes on exactly the change it exists to catch.
- **Assert the set in `install-test.sh`, against the installed result.** Rejected as 0045
  rejected it: it would make a source-tree question answerable only by running the installer.
- **A third script owning only skills membership.** Rejected: it would need its own copy of the
  workspace, fault, sort and comm machinery, a third recipe in the `verify` chain, and its own
  suite, to assert the same rule over a fourth tree.
- **Do nothing and rely on `check-skill-layout.sh` plus review.** Rejected on the asymmetry 0045
  named: a skill directory is a complete instruction set that lands in every user's global
  configuration and needs no further edit to keep acting, while the cost of the gate is one line
  per skill against two adding commits in the repository's history.
