# 0028 — Maintain Load-Bearing Coverage Claims Through Supersession

## Status

Accepted (2026-08-08)

## Context

ADR 0025 made the `testdata` exclusion entry-shaped: any file or directory named
`testdata` below `content/skills` is omitted from installed skill trees. It also
called its six-place inventory complete and named two ungated sites. Those claims
were accurate when accepted, but later changes deliberately changed both facts.

PR #70, resolving #60, added a fixture-repository case to `install-test.sh`. The
case plants a plain file named `testdata` below a fixture skill and runs that
copy's installer. It therefore exercises `stage_skills`; restoring the old
directory-only filter makes `just verify` fail. The case also adds another
operational use of the excluded name outside the three functions ADR 0025 listed.

The other gap was separate. The `check-skill-layout.sh` exclusion and the broader
unwired-suite recurrence were owned by debt 0012 and its linked work, including
#59. The fixture-repository case in #60 did not close that gap. Debt 0012 records
the sequence and its resolution rather than leaving #60 to imply wider coverage.

An accepted ADR is append-only except for lifecycle markers, so correcting these
present-tense guarantees in ADR 0025 would erase the state under which it was
accepted. Leaving them unqualified as historical observations would preserve the
text but make its explicitly load-bearing completeness claim unsafe to follow.

## Decision

Coverage claims that a decision makes load-bearing are maintained through a
superseding ADR. Historical context remains as-of-writing, but present-tense
inventories, coverage guarantees, and instructions whose staleness could weaken a
gate are not treated as implicitly historical. A later change that invalidates one
must either preserve it or supersede the record with the new state.

The `testdata` rule remains entry-shaped and name-based: a file or directory named
`testdata` at any depth below `content/skills` is excluded. Its coordination
inventory now has seven sites:

| place | how it applies or proves the rule |
|---|---|
| `install.sh` `stage_skills` | removes every matching entry from the staged copy |
| `install-test.sh` `assert_canonical_skills` | excludes the name from comparisons |
| `install-test.sh` `assert_no_test_suites` | asserts the installed suite inventory |
| `install-test.sh` `assert_no_stub_profile` | finds leftovers in installed skill trees |
| `install-test.sh` fixture-repository case | plants a plain file; copied installer removes it |
| `Justfile` skill recipes | keep excluded suites linted, formatted, and executed |
| deployment-reference and skill-layout checks | skip matches only below `content/skills` |

The last row groups the two deployment gates as one coordination site, as ADR 0025
did: `scripts/check-deployed-references.sh` and `scripts/check-skill-layout.sh`
apply the same deployment-boundary rule. The new seventh site is specifically the
fixture case's `fixture_entry=testdata`; renaming the entry-shaped exclusion must
update it as well as the six sites inherited from ADR 0025.

The fixture-repository case is the coverage for `stage_skills`. It installs from
a copied repository containing a fixture-only skill and a plain file named
`testdata`, then searches the complete installed skills tree for any entry with
that name. The fixture asserts the plant is a file, while the final search matches
either files or directories. This preserves both halves of the entry-shaped
contract and prevents a directory-only implementation from passing verification.

The `check-skill-layout.sh` history stays attributed to debt 0012 and #59. This
record does not claim #60 covered or closed that work; #60 covers only the
fixture-repository proof of `stage_skills`.

## Consequences

- Readers use ADR 0028 for the current coverage inventory and retain ADR 0025 as
  the historical explanation of the original decision.
- A present-tense coverage inventory in an accepted ADR creates maintenance work
  when its truth changes. Supersession preserves history while making that work
  visible instead of silently letting the claim decay.
- `testdata` remains a basename contract, not a directory contract. Tests and
  implementations must continue to accept either entry shape at any depth below
  `content/skills`.
- The seven-site list is a coordination inventory, not proof that every assertion
  independently covers every implementation. The fixture-repository case is the
  direct mutation-sensitive proof for `stage_skills`.
- Debt 0012 remains the historical owner for the distinct skill-layout and suite
  coverage gap. Its resolved status and #59 linkage are not rewritten or
  attributed to #60.

## Considered & rejected

- **Treat every accepted ADR as wholly as-of-writing.** Rejected because ADR 0025
  called its inventory complete and made coordinated edits depend on it. A reader
  cannot safely distinguish that instruction from ordinary historical context.
- **Rewrite ADR 0025 in place.** Rejected because accepted records are append-only
  except for lifecycle markers. It would remove the evidence of what was decided
  and covered on 2026-08-03.
- **Move the inventory into a new executable manifest.** Rejected as a speculative
  mechanism. The existing fixture and repository guardrails already decide the
  behavior; this change only needs to correct the policy and its inventory.
