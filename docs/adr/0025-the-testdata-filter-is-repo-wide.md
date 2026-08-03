# 0025 — The `testdata` Filter Is Repo-Wide, and a Delivered Suite Is Not a Test Asset

## Status

Accepted (2026-08-03)

## Context

ADR 0024 established that directories named `testdata` under `content/skills` are
test-only assets and are excluded from the installed payload. It applied that rule
to one skill — the tracker contract suite — and named the remaining three suites as
separate work. This record is that work, and it changes the rule in three ways, so
it supersedes 0024 rather than appending to it.

**The rule was never repo-wide.** `decision-records/assets/check-records-test.sh`,
`brainstorming/scripts/start-server-test.sh`, and
`issue/scripts/create-verified-issue-test.sh` still shipped to every installed tree.
A convention applied to exactly one skill is a special case wearing a convention's
name: the next suite added beside a skill's code has no rule to follow, because the
only evidence of the rule is one directory that already obeys it.

**Two gates model the install and disagree with the installer.**
`scripts/check-deployed-references.sh` builds its scan roots from all of
`content/skills`, and `scripts/check-skill-layout.sh` runs its
installed-config-root check (`~/.claude`, `$HOME/.codex`, …) over the same
unfiltered tree. Both are deployment rules: they exist because a *deployed* file
must not cite a repository-relative path or an installed config root. Neither
applies the exclusion the installer applies. Green today only because no fixture
under `testdata/` happens to contain such a string; the first one that does fails
`just verify` with a deployment finding about a file that is never deployed. ADR
0024's consequences named `stage_skills`, `install-test.sh`, and the `Justfile`
globs as the places the rule is written down. Neither appears on that list, and an
incomplete list is what let them drift.

**The filter matched directories only.** `stage_skills` filtered `-type d -name
testdata`, so a plain *file* named `testdata` shipped — and `install-test.sh`'s
`diff -rq -x testdata` excludes by basename regardless of type, so the canonical
comparison masked it in both directions. The hole and the thing that hides the hole
were introduced together.

**One of the three suites is not a test asset.** `decision-records/SKILL.md` tells
an agent to copy six files *out of the installed skill's `assets/` directory* into
an adopting repository's `.github/scripts/`, and `check-records-test.sh` is one of
the six. The skill's own text is explicit that the six install together and that
the suite must be run and green before the adopter commits. Excluding it from the
payload would leave an agent following those instructions unable to find a file the
instructions require — a documented procedure that fails when followed. That suite
is delivered content that happens to be a test, not a test-only asset of this
repository.

## Decision

**Test-only means test-only to this repository.** An asset is excluded from the
installed payload when no installed agent has a use for it. A suite a skill
instructs an agent to *deliver* to another repository is payload, and it ships.

The exclusion is now **entry-shaped, not directory-shaped**: any entry named
`testdata` under `content/skills` — regular file or directory — is test-only and is
removed from the staged tree. `stage_skills` drops `-type d`. This is the rule
`install-test.sh` already compared against, so the two now agree instead of one
masking the other. It stays a *name* rather than a path pattern: the concept is
"an entry called `testdata`", one predicate, decidable from a basename at any
depth, and a path-shaped variant would have to be restated in each of the six
places below rather than reused.

**The rule is written down in exactly six places, and this is the complete list:**

| place | how it applies the rule |
|---|---|
| `install.sh` `stage_skills` | removes the entries from the staged copy |
| `install-test.sh` `assert_canonical_skills` | `diff -rq -x testdata`, and the executable-mode comparison |
| `install-test.sh` `assert_no_test_suites` | asserts absence in each installed tree |
| `install-test.sh` `assert_no_stub_profile` | `find -name testdata` over each installed tree, asserting nothing named it survived |
| `Justfile` lint / format-check / format / test globs | keeps the excluded suites linted, formatted and run |
| `scripts/check-deployed-references.sh` and `scripts/check-skill-layout.sh` | skip the entries **under `content/skills` only**, because a never-deployed file cannot violate a deployment rule |

No gate infers the name from another; widening it means editing all six. That is
the property 0024 wanted and stated over an incomplete list. The
`assert_no_stub_profile` row is the one an enumeration most easily misses — it sits
in a function named for stub profiles — and missing it is not a false red: renaming
the excluded entry without editing it leaves `find -name testdata` matching nothing
and the assertion vacuously true.

**Two suites move; one stays.**

- `brainstorming/scripts/start-server-test.sh` moves to
  `brainstorming/scripts/testdata/start-server-test.sh`.
- `issue/scripts/create-verified-issue-test.sh` moves to
  `issue/scripts/testdata/create-verified-issue-test.sh`.
- `decision-records/assets/check-records-test.sh` **stays where it is and stays
  installed**, under the delivered-content rule above. The `just records`
  byte-for-byte comparison against `.github/scripts/check-records-test.sh` is
  therefore untouched, and so is `decision-records/SKILL.md`'s adoption table.

Each moved suite resolves the script it exercises one directory up rather than
beside itself. Both resolved it as a sibling of their own path, which is the
coupling the move breaks and the reason a move cannot be assumed safe: the suite
runs, so nothing but running it reports the break. `create-verified-issue-test.sh`
failed on the first run from its new path, and that is the whole argument for the
`Justfile` naming each moved suite explicitly rather than relying on a glob.

`start-server-test.sh` was reached by no `Justfile` recipe at all before this
change — not `test`, not `lint`, not `format-check`. `just test` now runs it and
`just lint` now covers it. The move is what surfaced that; a suite nobody runs is
the failure mode this record's own acceptance criterion names, and it was already
present.

That sweep covered `content/skills`, which is this record's subject, and it is not
a claim about the repository. `scripts/check-skill-layout-test.sh` is a second
unrun suite, and it fails when run — pre-existing, from a locale-dependent
character class rather than from anything here. It is tracked in
`docs/debt/0012-skill-layout-suite-is-unwired-and-locale-dependent.md`, not fixed
here: the remedy is a behavior change to an unrelated portability rule, and wiring
the suite in before that fix would turn `just verify` red.

## Consequences

- The installed payload carries no test suite for any of the three agent targets
  except `check-records-test.sh`, which is there because an agent is instructed to
  copy it onward. `install-test.sh` asserts that shape directly for claude, codex
  and bob: the two moved suites absent, `check-records-test.sh` present. Asserting
  the exception's *presence* is what keeps it a decision rather than an oversight —
  deleting it from the payload fails the gate and sends the author back here.
  That assertion enumerates the installed tree's `*-test.sh` files, so it enforces
  the repository's suite-naming convention rather than detecting tests as such: a
  suite named `foo_test.sh`, or written in another language, is not caught. Name a
  new suite `*-test.sh` and put it under `testdata/`. Deciding "is this a test"
  from content would be the suffix-based delivery rule rejected below, applied to a
  harder question.
- A plain file named `testdata` under `content/skills` no longer installs. Nothing
  has one; the change closes the gap between what the installer removed and what
  the canonical comparison already ignored, so a future one cannot ship unnoticed.
- `check-deployed-references.sh` and `check-skill-layout.sh` no longer scan
  `testdata` entries **under `content/skills`**. A fixture may now cite
  `docs/adr/0024-*.md` or `~/.claude` without failing a deployment gate, which is
  correct — it is not deployed — and is what makes fixtures usable for testing the
  deployment gates themselves.
- The scope of that narrowing is load-bearing and is asserted, not assumed.
  `content/skills` is the only root `stage_skills` filters; the `agents/*/shared`
  payloads install verbatim, and `agents/bob/shared/rules` is copied whole, so a
  `testdata` entry there does ship. Excluding the name across every scan root
  would blind the gate over a deployed path — the same
  disagreement-with-the-installer this record set out to end, pointing the other
  way. `check-deployed-references-test.sh` carries the pair that pins it: the
  fixture passes under `content/skills` and the identical fixture still fails
  under `agents/bob/shared/rules`. Reverting either half of the scoping turns one
  of the two red.
- Two of the six sites are not covered by a gate, and both are named here rather
  than left for a reader to discover.

  **`stage_skills`.** `install-test.sh`'s leftover check (`find -name testdata`)
  would catch a plain file named `testdata` that reached a destination tree, but
  nothing exercises `stage_skills` removing one, because the installer stages from
  the real repository and no such entry exists to inject. Reinstating `-type d`
  therefore leaves `just verify` green. Testing it would mean running the installer
  against a fixture tree, which the suite is not built for.

  **`check-skill-layout.sh`'s exclusion.** It has no case, and on today's tree it
  is inert: no file under `content/skills` matches the config-root pattern at all,
  inside `testdata/` or out, so reverting or mistyping a glob changes no verdict.
  The natural home for a case is `check-skill-layout-test.sh`, which already drives
  the script against a fixture root and already exercises the config-root rule — but
  that suite is wired to no recipe and fails on a UTF-8 host, so a case added there
  would run nowhere. Deferred to
  `docs/debt/0012-skill-layout-suite-is-unwired-and-locale-dependent.md` (tracker
  #56) with the suite itself.

  Only `check-deployed-references.sh`'s half of that table row is pinned, by the
  fixture pairs described above — one per scan site, because the exclusion is
  applied twice there and a bare-ADR payload exercises only the first. This
  paragraph is the record of the gap rather than a claim that it is covered.
- `check-deployed-references.sh` now scans every *directory* root the installer
  copies, which added `content/languages` and `content/references` — both deploy
  to all three agents through `install_common_content` and neither was scanned.
  The one deployed file it still does not scan is
  `docs/licenses/superpowers.LICENSE`, left out deliberately: admitting a single
  file means relaxing the is-a-directory guard or scanning `docs/licenses/` and
  excluding the undeployed `.md` beside it, which puts a deployed/undeployed split
  back in a second place. It is a verbatim vendored license, and a gate that
  invites editing one is worse than the reference it would catch.
- The payload claim above is about `skills/`. An upgrade from an install that
  predates this change keeps a copy of the previously installed tree — both
  removed suites and the `testdata` fixtures — under
  `<dest>/.agent-config-backups/<timestamp>/drift/skills/`, because
  `install_managed_path` backs up what it replaces and backups are a verbatim
  record, never filtered. Nothing prunes them. They are not a skills root and
  nothing loads from them, so the reachability the exclusion exists to remove is
  gone from the live tree; the copies are the user's to delete. `install-test.sh`
  pins the live half by seeding a stale suite into an installed tree and
  reinstalling, so the guarantee covers an upgrade and not only a fresh install.
- The `Justfile` gains `-i 2` for `brainstorming/scripts/testdata/*.sh`. The
  brainstorming scripts are vendored at two-space indent and are not covered by
  `format-check` today; formatting the moved suite to the repository default would
  have made a pure rename a rewrite and left it inconsistent with the script it
  tests. The indent follows the directory it came from.
- `just format` now writes `content/skills/issue/scripts/*.sh`, which
  `format-check` already checked. The two recipes disagreed, so `just format`
  could not fix a finding `just format-check` reported.
- Whether a suite ships is now a judgement about who consumes it, not about where
  it sits. That judgement has exactly one recorded answer today
  (`check-records-test.sh`), and adding another means adding a record — the
  `install-test.sh` assertion above is what forces that.

## Considered & rejected

- **Move `check-records-test.sh` under `testdata/` and re-point the `just records`
  comparison.** Mechanically easy — the comparison is one string in the recipe.
  Rejected because the comparison was never the real coupling: `decision-records/SKILL.md`
  directs an agent to copy the file out of the *installed* `assets/` directory, so
  filtering it breaks the skill's documented adoption at the point of use, and the
  breakage is invisible to every gate in this repository because the failure happens
  in the adopting repo.
- **Amend ADR 0024's consequences in place.** Rejected: the README states that
  merged records are append-only except for lifecycle markers, and that a new ADR
  is written instead of rewriting an accepted decision. The rule here genuinely
  changed — directory-shaped to entry-shaped, three places to six, plus an
  exception 0024 did not contemplate — so a supersession is the honest record and
  an appended bullet would have hidden a changed decision inside an unchanged one.
- **Make the rule path-shaped** (match `*/testdata/*` rather than the basename).
  Rejected as more surface for no coverage: the basename predicate already matches
  at every depth, and a path pattern would have to be spelled correctly and
  identically across the six places above, which match with five different
  syntaxes (`find -name`, `diff -x`, a shell `case`, `rg --glob`, and shell
  globs).
- **Exclude test suites by a `*-test.sh` suffix instead of a directory.** Rejected
  because it decides delivery from a filename, which is exactly the coupling that
  made `check-records-test.sh` ambiguous: two files with the same suffix, one
  delivered and one not. A directory is a place an author chooses deliberately.
- **Leave `start-server-test.sh` out of `just test`** and move it only. Rejected:
  the suite would then be excluded from the payload *and* run by nothing, which is
  strictly worse than shipping it. A test asset earns its exclusion by being run
  somewhere.
- **Add `brainstorming/scripts/*.sh` to `lint` and `format-check` wholesale.**
  Rejected as unrelated scope: the vendored scripts are clean under `shellcheck`
  but carry hundreds of `shfmt` differences, and reformatting vendored code in a
  change about install filtering would bury it. This change widens that asymmetry
  rather than creating it — the suite is now gated while the two shipped
  executables it exercises are not — so the gap is tracked in #57 rather than left
  in a sentence.
