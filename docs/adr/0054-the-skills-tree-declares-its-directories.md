# 0054 — The skills tree declares its directories

## Status

Accepted (2026-08-10)

## Context

Record 0045 gave three wholesale-installed trees a membership gate and left `content/skills`
out of it. The exclusion was a cost argument: `stage_skills` copies that tree with `cp -pR` and
prunes `testdata` from the staged copy, so 88 of its 96 tracked files are deployed content too,
but a per-file manifest over them would churn on ordinary work — eleven adding commits there
against one across the three covered trees at the time, and 132 commits touching
`content/skills` in the last 90 days against 6 for the three gated trees combined.

0045 recorded the resulting hole in its own Consequences: "a whole new top-level skill directory
[installs to every user] with no membership check". `check-skill-layout.sh` constrains what a
skill must *look* like — portable-ASCII paths, a valid `SKILL.md`, no symlinks, no reserved name
— and `scripts/reserved-skill-names.txt` is a forbidden list rather than an expected one.
Nothing declares which skills exist. The gate as merged covers 7 of the 95 installed content
files; the 88 it does not cover sit in 36 skill directories, any number of which could become 37
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
granularity.** 0045's siting objection is largely granted: the second half brings its own
enumerator, survival filter, sorts, comparisons, finding vocabulary, remedy line, summary clause
and emission block, and what the two halves actually share is the workspace, the `fault` helper,
the `LC_ALL=C` collation pin and the idea of set equality. The Consequences record that cost.
The siting rests on two grounds instead.

*The alternative siting mixes two subjects.* `check-skill-layout.sh` answers "is each skill
well-formed"; membership answers "which skills exist". Split that way, a reader asking what the
repository installs for every user reads two scripts and gets half the answer from each, with
neither summary stating the whole. Every fixture in `check-skill-layout-test.sh` builds a
one-skill tree and would have to carry a declaration matching it, so the rule's cost would also
land on 60-odd existing cases that are about something else.

*The receiving script's discipline is what a membership comparison needs, and the alternative
does not have it.* 0045's exit-code split — exit 1 for a difference found, exit 2 for input the
gate cannot make sense of, never the reverse — is load-bearing, because a membership answer an
unwritable `TMPDIR` can forge is not an answer; the receiving script routes every `mktemp`,
`sort`, `comm` and truncation through a `fault` helper for that reason. `check-skill-layout.sh`
exits 1 from `skill_error` for every condition it names, a missing `reserved-skill-names.txt`
included, so siting membership there means importing that discipline or accepting a rule whose
environmental failures read as findings.

**The declared unit is the directory name, and an entry that is not a directory is a finding
whatever the list says.** The line between what this gate re-checks and what it leaves to
`check-skill-layout.sh` is **containment**: a declared name resolving to a symlink makes this
gate's own declaration dishonest, since one line then admits whatever the target resolves to on
the user's machine, whereas a declared directory missing the `SKILL.md` `validate_inventory`
requires leaves the declaration accurate and only the skill malformed. Neither half is a bet on
whether the sibling gate regresses; the question is what a membership declaration can be read to
mean on its own. That is 0045's `non-regular-member` rule at the other granularity, and the
overlap with the shape gate is what containment costs.

**The three-tree block emits first, followed by the skills block.** The three trees' finding
classes, remedy line and emission order are unchanged, so 0045's suite rows that pin a whole
finding sequence keep asserting the same bytes. The summary gains one clause naming the declared
directory count, which edits the expected string in the rows that pin the summary in full.

## Consequences

- Adding a skill is now two edits: the directory, and the line in this gate that admits it.
  Removing one is likewise two. At two adding commits in the repository's history that is a cost
  the churn objection cannot reach, but it is not zero — a wave that adds a skill on one branch
  turns a sibling branch red after it merges, and the remedy is the one-line edit.
- What the gate proves is that an *undeclared* skill directory cannot land silently — CI refuses
  it whether or not anyone reads the diff. It does not make the list line more conspicuous than
  the directory beside it in the same commit; if anything less so, since the added artifact here
  is a whole `SKILL.md`-bearing tree. 0045 qualified its own claim the same way.
- **What remains uncovered, stated rather than implied away:**
  - *Membership inside a skill directory.* A file added under an existing
    `content/skills/<name>/` — an asset, a carrier, a second Markdown file — still installs with
    no membership check. This is the residual the issue books deliberately, and it is the larger
    half by file count: 88 installed files sit inside the 36 declared directories, plus 8 more
    under `testdata` that `stage_skills` prunes before delivery. `check-skill-layout.sh`
    constrains what those files may be named, contain and reference; nothing counts them. The
    containment rule above stops at depth one for the same reason: a committed
    `content/skills/<name>/link -> /` is refused only by `validate_portable_tree`, so inside a
    declared directory this record does take the bet on the sibling gate that its top-level rule
    declines to take.
  - *The manifest is source, so the gate cannot defend against edits to itself.* Deleting a
    declared name while the directory is there makes the directory undeclared, which is red.
    Deleting a name and its directory together is green, and correctly so — that is a removal.
    What survives is a coordinated edit to this script's lists and the suite's, exactly as 0045
    records for the file-granularity half.
  - *Nothing couples the declaration to `install.sh`.* A fifth wholesale-installed tree added to
    the installer is uncovered until someone adds it here, and no gate detects the omission. The
    coupling is still only comments: this change corrects the stale clause in
    `install_common_content` and puts the skills half's pointer in `stage_skills`, which is the
    one function all three skill call sites go through.
  - *The declared set is the source tree's children, not the delivered set.* `stage_skills`
    prunes `testdata` at any depth, so a declared top-level `content/skills/testdata/` would pass
    this gate and `check-skill-layout.sh` alike and never install — the one way a declared name
    can fail to reach a user. Naming it is the remedy; `reserved-skill-names.txt` is another
    change's surface.
  - *A second, ungated enumeration of skill directory names.* `docs/licenses/superpowers.md`
    lists eleven of them as the covered roots of the vendored MIT attribution, and no script,
    workflow or recipe reads it. A rename now turns this gate red, which prompts an edit to
    *this* list while the licensing one goes stale in the same commit. Issue #159 owns it.
  - *Directory names only.* The gate says nothing about whether a declared skill should ship, or
    what it contains.
  - *A skills-side fault now withholds the three-tree findings of the same run.* Every
    comparison completes before any finding is emitted, so an unreadable skills tree or a name
    holding a newline exits 2 with its own diagnostic and the `unexpected-member` line that
    would have printed does not. Nothing is lost silently; the operator gets one answer where
    they would previously have had two, and re-running after the fault gives the other.
  - *The sibling gate this record argues from is itself undisciplined.* `check-skill-layout.sh`
    exits 1 for every condition it names, including a missing `reserved-skill-names.txt` and an
    unwritable scan sink, so a fault there is indistinguishable from a finding. The siting
    argument above leans on that and does not fix it — the sibling gates were outside this
    change. Issue #158 owns it.
- 0045's debris false positive now reaches `content/skills`, narrowed twice over: the
  enumeration prunes at depth one, and `check-skill-layout.sh` already reddens most top-level
  debris on its name rules. What is left is an author's undeclared local draft directory, which
  reddens a `just verify` that neither `verify-push.sh` nor CI sees. The remedy is the
  declaration.
- The repository now has two answers to "what installs for every user" in one script and at two
  granularities. A reader has to know which tree they are asking about; the summary line names
  both counts so the split is visible rather than inferred.
- `examples/project-review-skills/` is untouched — it is a documented non-installed exception
  (record 0020) and gating it as installed would be wrong. `check-skill-layout.sh` continues to
  be the only gate that reads it.

## Considered & rejected

- **Put the declaration in `check-skill-layout.sh`, as 0045 proposed.** The closest thing to a
  settled position, and the issue names it too. Rejected on the grounds in the Decision.
- **Declare `content/skills/*/SKILL.md` as ordinary file members instead of declaring
  directories.** The smallest alternative available — no second granularity, no new member
  class, and the existing `non-regular-member` rule covers a symlinked `SKILL.md` unchanged.
  Rejected because it declares a proxy for the thing installed rather than the thing itself:
  what this gate would then prove is that the expected set of *required files* is intact, and
  the directory the installer actually copies is admitted only as a side effect of a rule that
  lives in another script. It needs a second enumerator regardless — adding `content/skills` to
  the existing tree list enumerates all 96 tracked files, not the 36 directories.
- **Reuse `unexpected-member` and `missing-member` for the skills half rather than minting a
  parallel vocabulary.** Most of the cost the Decision concedes is here, so it is worth naming.
  Rejected on the noun: this script defines a member as an entry under a declared tree that is
  *not* a directory, and its summary counts declared members on that definition, so
  `missing-member: content/skills/foo` would either contradict the definition or fold 36
  directories into a count that means files. The third class has no counterpart either — a
  stray regular file at the top level is precisely not a `non-regular-member`.
- **Assert an expected count rather than an expected set.** `validate_inventory` already returns
  the number of top-level children, so a count is nearly free. Rejected because it is blind to
  the two changes most worth catching: a rename, and an addition landing in the same commit as a
  removal, both of which leave the count intact.
- **Declaring the directories *and* their `SKILL.md`; declaring the 88 installed files inside
  them; a data file beside `reserved-skill-names.txt`; a set derived from `git ls-files` or from
  the tree; an assertion in `install-test.sh` against the installed result; a third script owning
  only skills membership.** All rejected for reasons already on record and undisturbed by the
  change of granularity — the required file is `validate_inventory`'s rule, a per-file manifest
  is the churn 0045 measured, an inline list means nothing apart from the comparison that
  consumes it, a derived list agrees with whatever is there, an installed-result assertion makes
  a source-tree question answerable only by running the installer, and a third script would
  be a second place a reader has to look to learn what installs for every user.
- **Do nothing and rely on `check-skill-layout.sh` plus review.** The null option is stronger
  here than it was in 0045: `validate_inventory` already requires every top-level child to be a
  real directory with a portable non-reserved name and a valid UTF-8 `SKILL.md`, so what this
  gate adds is refusal of a well-formed skill directory that arrives *undeclared* — in practice
  the sibling branch that forgot the line, since a merge artefact or a duplicated directory
  already fails on the name and frontmatter rules. Rejected anyway on the asymmetry: such a directory is a complete instruction set that
  lands in every user's global configuration and needs no further edit to keep acting, against a
  cost of one line per skill at two adding commits in the repository's history.
