# Vendored Superpowers Attribution and Ownership Design

Issues: [#6](https://github.com/randomparity/agent-config/issues/6) and
[#13](https://github.com/randomparity/agent-config/issues/13)

ADR: [0004. Own vendored Superpowers skills as maintained agent projections][adr-0004]

Debt: [0002. Non-lifecycle vendored skills retain human-only gates][debt-0002]

## Goal

Restore the license and attribution omitted when Superpowers-derived skills were imported,
and state the repository's present ownership, update, and dispatched-mode policy for all
applicable Claude, Codex, and IBM Bob projections. Migrate the predecessor's remaining
human-gate concern into one target-owned debt record grounded in the current projections.

## Requirements and assumptions

- Preserve the upstream MIT license text from Superpowers 6.1.1, copyright Jesse Vincent.
- Distribute local modifications within the covered derived roots under the same MIT
  terms, as explicitly confirmed by the repository owner. Future covered-root
  submissions expressly offer the change under MIT and represent the contributor's
  authority to grant those rights; the README and attribution notice publish that rule.
- Attribute every file in each current derived skill root, including local additions and
  modifications beneath those roots.
- Record the canonical upstream repository, tag `v6.1.1`, and exact commit
  `d884ae04edebef577e82ff7c4e143debd0bbec99` in the attribution inventory.
- Make license and additional-notice compatibility a re-vendor precondition. An
  incompatible upstream revision requires a superseding ADR before import.
- Treat the predecessor repository's ADRs 0015 and 0018 and debt 0009 as provenance, not
  as policy to copy. This repository has native multi-agent projections and no dependency
  on the old Claude plugin arrangement.
- Reserve ADR 0004 for issue #6 and debt 0002 for issue #13. The directory listing is the
  record index; no hand-maintained index is added.
- Install the canonical license with every Claude, Codex, and Bob target that receives
  derived skills. Do not create independently edited projection license sources.
- Do not re-vendor skill contents, add a generator, or change runtime skill behavior.
- Use both issues' acceptance criteria and the operator's two resolved decisions as the
  approved requirement in dispatched design mode.

## Provenance audit

The upstream source is [obra/superpowers at v6.1.1][superpowers-611], whose annotated tag
resolves to commit `d884ae04edebef577e82ff7c4e143debd0bbec99`. Its `LICENSE` blob is
identical to the predecessor's `docs/licenses/superpowers.LICENSE`. Repository history
shows all current derived roots arrived in the initial public agent-payload commit. The
predecessor's ADR 0015 identifies the eleven selected skill families; the current tree
projects those eleven to Claude and Codex and projects two applicable skills to Bob.

The attribution notice will define coverage by directory root. That makes every current
file below a listed root covered even when an agent projection has local helper files or
differs from the upstream snapshot.

## Human-gate audit

The audit distinguishes instructions that can stop or redirect execution from examples
and historical prose that require no action:

| Skill or companion | Claude | Codex | Bob | Classification |
|---|---|---|---|---|
| `test-driven-development/SKILL.md` | deployed | deployed | deployed | executable gates |
| `testing-anti-patterns.md` | deployed | deployed | absent | descriptive quotes |
| `systematic-debugging/SKILL.md` | deployed | deployed | absent | executable gate |
| `receiving-code-review/SKILL.md` | deployed | deployed | absent | mixed; gates recorded |
| `verification-before-completion/SKILL.md` | deployed | deployed | deployed | descriptive history |
| `using-git-worktrees/SKILL.md` | deployed | deployed | absent | lifecycle; outside debt 0002 |

The TDD gates require human permission for exceptions and send an unknown test strategy
to the human. Systematic debugging requires discussion after three failed fixes.
Review-reception stops for clarification or direction on unclear and unverifiable
feedback, on conflicts with prior human decisions, and for architectural escalation; its
example speakers and quoted preferences are descriptive. Verification's single phrase
reports a past loss of trust and is not a gate. Debt 0002 owns only the executable
residuals inside issue #13's explicit test, debugging, review-reception, and verification
boundary and names only the projections that actually deploy them.

`using-git-worktrees` is a lifecycle skill outside that boundary, not an omitted audit
result. Caller-assigned worktree instructions resolve its creation-consent gate. Its
baseline-failure prompt does not yet return a blocker to a dispatched caller, so
[issue #23][issue-23] owns that separate lifecycle fix under ADR 0004.

## Approaches considered

### Repository license plus root inventory — selected

Add the exact upstream license once, add a notice that names the source snapshot and every
covered projection root, and link both from the README and ADR 0004. This is explicit,
keeps the license authoritative, and handles locally added files beneath derived roots.

### Per-directory license copies

Place a license beside every projected skill. This is locally visible but repeats the
same legal text across 24 roots and creates unnecessary drift and review noise.

### Repository-only license

Leave the license under `docs/licenses/` and depend on users retaining the checkout. This
does not cover the installer's normal distribution path, which copies derived skill trees
into agent configuration directories without the repository documentation tree.

### Canonical vendored tree with generated projections

Move derived files into one canonical tree and generate per-agent copies. This might
simplify future attribution, but it changes the repository's ownership and installation
architecture and is not required to restore the missing records.

### Copy the predecessor debt unchanged

This would preserve its wording but retain Claude-only `shared/skills/` targets and treat
its four named skills as if all agents deployed them. A new target record instead records
the current projection matrix and separates executable gates from descriptive references.

## Design

Create `docs/licenses/superpowers.LICENSE` as a byte-for-byte copy of the upstream
Superpowers 6.1.1 MIT license. Create `docs/licenses/superpowers.md` as the human-readable
notice. It records the upstream project, exact tag and commit, upstream copyright, and MIT
coverage of local modifications; links the license and predecessor provenance; and lists
the covered skill roots by agent and skill name. It also states the covered-root inbound
MIT offer and authority representation.

Add a short README section that points readers to the notice and license rather than
duplicating the inventory, and tells contributors that submitting a covered-root change
offers it under MIT while representing authority to do so. Git history retains the merged
submission. ADR 0004 owns the durable policy:

- native projection directories are maintained forks distributed under MIT;
- updates are deliberate upstream diffs that preserve and review local adaptations;
- re-vendor updates verify license and notice compatibility before importing;
- all applicable projections are considered together, without requiring byte identity;
- a caller explicitly asserts dispatched mode;
- dispatched gates target resolution from written policy or a returned blocker, never
  inferred permission; debt 0002 enumerates the scoped issue #13 exceptions, while
  lifecycle exceptions remain governed and tracked separately;
- later shipping skills retain their own push and merge authorization.

Extend the existing `install_common_content` entry point in `install.sh`. It installs the
single canonical `docs/licenses/superpowers.LICENSE` source at
`licenses/superpowers.LICENSE` under each agent target. Because the path goes through
`install_managed_path`, it participates in the existing source validation, safe-parent,
drift backup, manifest, and pruning behavior. `install-test.sh` compares each installed
license byte-for-byte with the canonical source after `--agent all`.

Create debt 0002 for the audited residual TDD, debugging, and review-reception gates and
the descriptive verification reference. It records the scoped projection matrix,
sanctioned resolution choices, non-regression boundary, predecessor commit, and a
2026-10-31 review date.
Closing issue #13 means the migration is complete; the record remains open until the skill
adaptations and proofs it names land.

No skill body or installer architecture changes. The existing directory layout remains
the source of deployable agent-native files.

## Failure handling and maintenance

- A missing or altered license is visible as a normal repository diff and fails review;
  the implementation copies the source blob already verified against upstream and the
  predecessor repository.
- A missing canonical source makes `install_managed_path` fail with its existing
  actionable missing-source error. Installed drift follows the existing backup and
  replacement behavior rather than a license-specific path.
- A future derived root not present in the notice is an incomplete re-vendor change under
  ADR 0004. Its author must update the inventory in the same change.
- Agent-specific differences are reviewed for semantic policy coverage. They are not
  normalized merely to make files match.
- If upstream changes license terms, the re-vendor change must retain the terms applying
  to existing material and add the new terms required by the incoming snapshot.
- A future dispatched call into a recorded human gate must return a blocker unless written
  policy fully decides the choice. It may not treat silence as permission.
- Debt 0002's review date bounds re-evaluation even if no upstream refresh occurs; an
  observed skipped or weakened test triggers earlier review.

## Verification

- Compare `docs/licenses/superpowers.LICENSE` byte-for-byte with the verified upstream
  v6.1.1 license blob.
- Run the installer test red before the common install step changes, then green after each
  Claude, Codex, and Bob target contains a byte-identical managed license.
- Enumerate the current derived roots and confirm each appears in the attribution notice.
- Repeat the issue #13 human-reference sweep and confirm each test, debugging,
  review-reception, and verification result is classified by debt 0002 or documented as
  descriptive or inapplicable. Confirm lifecycle skills are explicitly excluded rather
  than silently treated as covered.
- Run the decision-record checker for ADR 0004 and debt 0002.
- Run `just verify`, including public-safety, documentation-adjacent record checks, install
  tests, shell lint and formatting, and workflow checks.
- Review the final diff to ensure it contains no host-specific or private material and no
  skill or installer behavior change.

## Scope and decomposition

The operator authorized issue #6 to absorb issue #13 because the general dispatched policy
and its current residual must be reviewed together. The license, notice, installer path,
installer test, README link, ADR, debt record, and design/plan artifacts are one consistency
unit and ship in one pull request that closes both trackers. Runtime skill adaptations
remain deferred to debt 0002.

[adr-0004]: ../../adr/0004-own-vendored-superpowers-skills.md
[debt-0002]: ../../debt/0002-non-lifecycle-vendored-skills-retain-human-gates.md
[superpowers-611]: https://github.com/obra/superpowers/tree/v6.1.1
[issue-23]: https://github.com/randomparity/agent-config/issues/23
