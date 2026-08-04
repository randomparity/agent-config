# 0026 — A Suite Is Reached by a Recipe, or It Is a Byte-Identical Copy of One

## Status

Accepted (2026-08-03)

## Context

ADR 0025 decided that suite wiring in the `Justfile` is enumerated by hand rather
than globbed, because a glob would have run the moved suites from their new paths
without anyone noticing that one of them resolved its subject as a sibling and
broke. That argument holds. Its cost is that the enumeration can be incomplete and
nothing says so: a suite no recipe names is indistinguishable from a suite that
passes.

Two instances are on record, each found by accident.
`brainstorming/scripts/start-server-test.sh` was reached by no recipe at all — not
`test`, not `lint`, not `format-check` — from the day it was added until ADR 0025
moved it. `scripts/check-skill-layout-test.sh` was unrun from the day it was
written, and while unrun it accumulated two live defects (a locale-dependent
character class that never bit on a UTF-8 host, and a fixture that stopped matching
its subject after PR #58 added a fail-closed guard). `docs/debt/0012` records the
recurrence rather than either instance, and names this work as its owner.

Issue #59 sketches the gate: enumerate with `git ls-files`, resolve what the
recipes actually run from `just --dry-run` rather than grepping the `Justfile` for
literal strings, fail with the unreached path and the recipe it belongs in, and run
from `just verify`. Four properties of `just --dry-run` as it behaves here decide
the shape, and three of them are not obvious.

**It does not expand a shebang recipe.** The issue's premise that dry-run "expands
each recipe to the commands it will execute" is true for a plain recipe and false
for a shebang recipe: `just --dry-run test` prints its suite invocations one per
line, and `just --dry-run records` prints the recipe *source*, `for` loop and all. A gate that reads dry-run output is reading two different things and has to be
correct for both.

**It writes to stderr, not stdout.** All five recipes below print nothing on
stdout. A gate that captures `$(just --dry-run test)` gets the empty string and
reports every suite unreached — red, but for a reason with no connection to the
mistake.

**It passes recipe-body comments through verbatim**, for plain recipes as well as
shebang ones. `just 1.55.1` prints `# ./scripts/foo-test.sh` for a commented-out
invocation. Commenting out a line is the ordinary way a suite gets disabled, so a
gate that treats dry-run output as "what will run" is green over exactly that.

**It includes a recipe's dependencies' commands.** `just --dry-run dep` where
`dep: plain` prints `plain`'s body too.

Two further facts about the repository decide the rest.

**One tracked suite is executed by no recipe, by decision.**
`content/skills/decision-records/assets/check-records-test.sh` is a copy of
`.github/scripts/check-records-test.sh`. ADR 0025 decided it stays under `assets/`
and stays installed, because `decision-records/SKILL.md` instructs an agent to copy
it out of the installed tree into an adopting repository. `just records` executes
the root copy and then byte-compares five shared assets, this suite among them. So
the file is verified, but it is never invoked, and its full path never appears in
any dry-run output — the `records` loop builds it from `$asset`. Matching on the
basename instead would mark it reached, but the basename is shared by the root copy
and appears in the recipe source as a bare literal word, so basename matching would
report the pair as covered whatever happened to either file.

**The other three dimensions of ADR 0025's `Justfile` row are checkable too.** That
row reads "lint / format-check / format / test globs", and `start-server-test.sh`
missed all four. `just --dry-run lint` emits `shellcheck …` with the globs
*unexpanded*, so a gate that wants those dimensions has to expand them itself.

## Decision

**`scripts/check-suite-coverage.sh` enumerates every tracked `*-test.sh` and
requires each to be reached in four dimensions.** It is invoked by the
`suites-check` recipe, which `verify` depends on, so the pre-commit hook and CI both
enforce it. It resolves the repository root from its own location and works there,
so its verdict does not depend on the caller's working directory.

**Coverage is decided by expanding dry-run output as pathnames, not by matching
strings.** For each dimension the gate runs `just --dry-run <recipe> 2>&1` — stderr
merged, per the property above — and reads the result line by line. Each line is
split into words with the shell performing *pathname* expansion and nothing else:
no `eval`, so a word carrying `$asset` or `"$root_asset"` stays literal and matches
nothing. A line is abandoned at its first word beginning with `#`, which discards
both a commented-out invocation and a shebang recipe's `#!` line. Any surviving
word that resolves to an existing file, after a leading `./` is stripped, is a path
the recipe named; both sides of the comparison are canonicalized the same way,
because `git ls-files` yields `install-test.sh` where `test` yields
`./install-test.sh`.

This one rule reads both kinds of dry-run output. Against `test` the words are
already whole paths and expansion is the identity. Against `lint` the words are
globs and expansion is what the recipe's own shell would have done. Against the
`records` source dump, `./.github/scripts/check-records-test.sh` is a word like any
other. The gate never needs to know which recipes are shebang recipes, which words
are flags, or what `shfmt -i 2` means: a flag expands to itself, is not a file, and
drops out.

The rule's one failure direction that matters is a word admitted to the covered set
that the recipe did not really name — a false green, which is the thing this gate
exists to prevent. It requires a word that is not a path yet resolves to a tracked
suite. One such word exists today: `shared_assets="check-records.sh` splits to leave
a bare `check-records-test.sh`, which resolves to nothing only because no file of
that name sits at the repository root. A tracked suite added at the repository
root whose basename also appears as a bare word in a scanned recipe would be
cleared wrongly. That is the known hole, and it is narrow enough to name rather
than to build parsing for: the rule that would close it — abandon a line whose
first word is an assignment — buys a contrived false green at the price of a
plausible false red, the day someone lifts a recipe's paths into a variable.

Two nearby holes are closed rather than named, because both are cheap. A suite
name carrying a glob metacharacter is compared literally, not as a pattern, so it
cannot match some other covered path; and a name carrying whitespace is refused by
name, because output read by word cannot be seen to contain it. The gate works
from the repository root rather than the caller's directory, so its verdict does
not move with the caller — that much the suite asserts.

**The dimensions keep separate recipe lists:**

| dimension | recipes |
|---|---|
| executed | `test`, `records` |
| linted | `lint` |
| format-checked | `format-check` |
| formatted | `format` |

`test` and `records` share a dimension because a suite is executed if *either* runs
it. Every other dimension holds exactly one recipe, and `format-check` and `format`
are deliberately not merged: the defect ADR 0025 records is `just format` not
writing a path `just format-check` checked, and a union over the two recipes is
green over precisely that. They resolve identical sets today, so the split costs one
`just` invocation and buys the disagreement.

The dimensions are kept apart at all because a single merged scan would report a
suite that is only *linted* as run. `verify` reaches every one of these recipes
except `format`, which writes and so is a check's fixer rather than a check.

That separation holds only while the five recipes stand alone: `test: lint` would
fold the linted set into the executed one and go green over a suite nothing runs.
None has a dependency today, and the gate reads `just --dump --dump-format json`
and refuses to scan a recipe that has one, rather than reporting over a merged
set. `jq` is already a prerequisite `tools-check` pins, so that check adds no tool.

Adding an execution recipe means adding it to this table. That is one more
hand-maintained list, and it is deliberate for the same reason ADR 0025 gave: the
failure mode is a red gate naming a suite that *is* wired, which sends the author to
the list. The inference-shaped alternative fails silently in the other direction. A
renamed recipe is caught without a rule, because `just --dry-run <gone>` exits
non-zero and the gate runs under `set -e`.

**A suite that is byte-identical to a reached suite is reached, in that
dimension.** This is the rule for the mirrored decision-records asset, and it is
stated generally because it is generally true, not because one file needs an
exemption. `cmp` establishes that the two files contain the same assertions, so
executing one executes them; `shellcheck` and `shfmt` decide a file from its content
and the flags it is given, so a copy under identical flags is decided identically.
The gate prints each suite it clears this way and the reached copy it matched, so
the exemption is visible in the gate's own output rather than implied by its
silence.

The rule is recomputed every run and holds nothing on trust. Diverge the two copies
and the gate goes red the same day.

Its limit is that a suite resolving a subject relative to its own location is
exercised only against the executed copy's neighbours, and in this repository the
limit is narrowed but **not** closed. `just records` pins five of the six files
`decision-records/SKILL.md` tells an adopter to copy, so those neighbours cannot
drift. The sixth, `records.yml`, is outside that loop by design — the suite's
`find_template` resolves it from either of two layouts and fails at its use site —
and it *is* a neighbour the suite loads out of `$SCRIPT_DIR`. Editing only
`content/skills/decision-records/assets/records.yml` therefore leaves both `just
records` and this gate green while the skill copy's adoption cases would have run
against a different template. That gap predates this gate and is not created by it;
it is filed as #71 rather than fixed here. The honest boundary is that this gate
certifies the assertions run, not that they ran against every subject.

**`lint`, `format-check` and `format` are in scope.** The token-expansion rule is
what makes them affordable: they cost three more `just --dry-run` calls and no new
parsing, and the gate is green over them today without a single `Justfile` edit.
Scoping them out would have left the exact miss ADR 0025 recorded — a suite in a
directory no glob names — undetected in three of the four recipes its table's
`Justfile` row lists.

**The gate fails closed on an empty enumeration.** If `git ls-files '*-test.sh'`
returns nothing, the gate exits non-zero rather than reporting success over zero
suites.

## Consequences

- `docs/debt/0012`'s recurrence is closed. The gate reports the class, so the next
  unwired suite fails `just verify` on the commit that adds it instead of being
  found by accident some releases later.
- ADR 0025's `Justfile` row is now enforced for `*-test.sh` entries in all four of
  its recipes. That row was not previously named as unchecked — ADR 0025 names
  `stage_skills` and `check-skill-layout.sh`'s exclusion as its two uncovered
  sites, and `docs/debt/0012`'s second deferral (#60) owns the first of those — so
  this gate adds a check the table did not claim to be missing, over the row most
  likely to go stale. It says nothing about the other five rows.
- The gate does not report itself. `scripts/check-suite-coverage.sh` is not a
  `*-test.sh` and is never enumerated, and `scripts/check-suite-coverage-test.sh`
  is wired into `test` like any other suite and reached like any other suite — so
  the self-exemption issue #59 anticipated does not arise and no special case
  exists for it.
- The gate depends on `just --dry-run` output, which is not a stable interface. The
  dependency is narrow: it needs the output on stderr to contain the paths a recipe
  names, in any order, on any line, with `#` retaining its comment meaning. A
  formatting change that preserves the paths does not affect the gate, and one that
  drops them turns it red rather than green. `just` and `jq` are both already hard
  prerequisites pinned by `tools-check`, so the gate adds no new tool.
- `just --dry-run format` is scanned even though `format` writes. Dry-run runs
  nothing and does not evaluate a `shell()` or backtick assignment, so scanning a
  writing recipe has no side effect; that was verified rather than assumed.
- Coverage is asserted over *tracked* files. An untracked spike or a copy under
  `/tmp` does not fail the gate, and a suite is enumerated the moment it is
  `git add`ed — which is before the pre-commit hook runs, so a new suite fails the
  commit that introduces it unwired.
- The gate does not check that a suite is formatted at the right `shfmt` indent,
  only that a recipe names it. Pinning the indent would mean reading flags, which is
  the parsing this record's rule exists to avoid, and getting it wrong is a
  `format-check` failure on the next run rather than a silent gap.

## Considered & rejected

- **Match suite basenames instead of full paths.** Rejected: `check-records-test.sh`
  is the basename of two tracked files, and the string appears literally in the
  `records` recipe source as an element of `shared_assets`. Basename matching marks
  both copies reached, permanently, whatever either file's wiring — the gate would
  be green over the one case that motivated writing it.
- **An allowlist file naming each exempt suite and its reason**, the fallback issue
  #59 permits. Rejected in favour of the byte-identity rule. An allowlist is an
  assertion a human wrote once; it stays green after the reason for it is gone, and
  the only thing that removes a stale entry is someone noticing. Byte-identity is
  recomputed from the files on every run and cannot outlive its justification. It
  is also testable against a fixture repository with no configuration to keep in
  step, where an allowlist naming real repository paths would have to be recreated
  inside every fixture.
- **Treat a suite as reached if it appears in the first word of a dry-run line**,
  distinguishing an executed command from an argument passed to `shellcheck`. That
  would let a single scan of `just --dry-run verify` follow any recipe added to the
  guardrail chain without a hand-maintained table. Rejected as a trade of an
  explicit table for a fragile heuristic: `bash ./scripts/foo-test.sh`,
  `env FOO=1 ./scripts/foo-test.sh`, or an invocation inside an `if` all read as
  arguments, and each would report a wired suite as unreached for a reason with no
  connection to what the author did wrong.
- **Grep the `Justfile` for each suite path.** Rejected for the reason issue #59
  gives: it reads the recipe as text, so it survives no restructuring, and it
  cannot tell a path in the `test` recipe from the same path in `format`. Note that
  dry-run output is not categorically better than text here — comments survive it
  verbatim, which is why the `#` rule above exists — but it is what `just`
  resolved: dependencies, shebang bodies and all, rather than what the file happens
  to spell.
- **Extend the gate to assert the `shfmt` indent each suite is formatted at.**
  Rejected: it requires classifying words as flags or paths, which is exactly the
  parsing the token-expansion rule removes, and the failure it would catch —
  a suite formatted at the wrong indent — is already caught by `format-check` on
  the next run, loudly and with a diff.
- **Scope `lint`, `format-check` and `format` out and gate execution only.**
  Rejected: the miss that motivated ADR 0025 covered all four recipes, and under
  the token-expansion rule the three extra dimensions cost three dry-run calls and
  no additional parsing. There was a cost to weigh only under a design that had to
  expand the globs by hand.
- **Pin `records.yml` into the `just records` comparison here**, closing the
  byte-identity limit described above. Rejected as scope: it changes what the
  `records` gate asserts about an unrelated file, in a change about suite
  reachability, and the gap it closes predates this gate. Filed as #71 instead.
