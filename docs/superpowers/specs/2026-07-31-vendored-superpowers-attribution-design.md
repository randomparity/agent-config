# Vendored Superpowers Attribution and Ownership Design

Issues: [#6](https://github.com/randomparity/agent-config/issues/6) and
[#13](https://github.com/randomparity/agent-config/issues/13)

ADR: [0005. Own vendored Superpowers skills as maintained canonical packages][adr-0005]

Debt: [0002. Non-lifecycle vendored skills retain human-only gates][debt-0002]

## Goal

Restore the license and attribution omitted when Superpowers-derived skills were imported,
and state the repository's present ownership, update, and dispatched-mode policy for the
canonical packages installed for Claude, Codex, and IBM Bob. Migrate the predecessor's
remaining scoped human-gate concern into one target-owned debt record grounded in the
current canonical tree.

## Requirements and assumptions

- Preserve the upstream MIT license text from Superpowers 6.1.1, copyright Jesse Vincent.
- Distribute local modifications within the covered derived roots under the same MIT
  terms, as explicitly confirmed by the repository owner. Future covered-root submissions
  expressly offer the change under MIT and represent the contributor's authority to grant
  those rights; the README and attribution notice publish that rule.
- Attribute every file in each current canonical derived package root, including local
  additions and modifications beneath those roots.
- Record the canonical upstream repository, tag `v6.1.1`, and exact commit
  `d884ae04edebef577e82ff7c4e143debd0bbec99` in the attribution inventory.
- Make license and additional-notice compatibility a re-vendor precondition. An
  incompatible upstream revision requires a superseding ADR before import.
- Treat the predecessor repository's ADRs 0015 and 0018 and debt 0009 as provenance, not
  as policy to copy. This repository uses the canonical skill ownership established by
  ADR 0004, not the old Claude plugin arrangement.
- Reserve ADR 0005 for issue #6 and debt 0002 for issue #13. The directory listing is the
  record index; no hand-maintained index is added.
- Install the canonical license with every Claude, Codex, and Bob target that receives the
  canonical skill tree. Do not create independently edited target license sources.
- Do not re-vendor skill contents, add a generator, or change runtime skill behavior.
- Use both issues' acceptance criteria and the operator's resolved licensing and combined
  scope decisions as the approved requirement in dispatched design mode.

## Provenance audit

The upstream source is [obra/superpowers at v6.1.1][superpowers-611], whose annotated tag
resolves to commit `d884ae04edebef577e82ff7c4e143debd0bbec99`. Its `LICENSE` blob is
identical to the predecessor's `docs/licenses/superpowers.LICENSE`. The predecessor's ADR
0015 identifies eleven selected skill families. After ADR 0004's canonicalization, those
families have one source each under `content/skills/`, and the installer copies the exact
canonical tree to Claude, Codex, and Bob.

The independently derived expected inventory is these eleven canonical roots:

| Derived family | Canonical source | Installed targets |
|---|---|---|
| `brainstorming` | `content/skills/brainstorming/` | all three |
| `writing-plans` | `content/skills/writing-plans/` | all three |
| `executing-plans` | `content/skills/executing-plans/` | all three |
| `subagent-driven-development` | `content/skills/subagent-driven-development/` | all three |
| `test-driven-development` | `content/skills/test-driven-development/` | all three |
| `systematic-debugging` | `content/skills/systematic-debugging/` | all three |
| `finishing-a-development-branch` | `content/skills/finishing-a-development-branch/` | all three |
| `using-git-worktrees` | `content/skills/using-git-worktrees/` | all three |
| `receiving-code-review` | `content/skills/receiving-code-review/` | all three |
| `requesting-code-review` | `content/skills/requesting-code-review/` | all three |
| `verification-before-completion` | `content/skills/verification-before-completion/` | all three |

The attribution notice defines coverage by canonical directory root. Every file below a
listed root is covered even when a package has local helper files or differs from the
upstream snapshot. Installed copies are outputs of those roots, not additional source
roots requiring duplicate inventory entries.

## Human-gate audit

The issue #13 audit distinguishes instructions that can stop or redirect execution from
examples and historical prose that require no action. Because all agents receive the exact
canonical tree, each source classification applies to Claude, Codex, and Bob:

| Canonical package or companion | Classification |
|---|---|
| `test-driven-development/SKILL.md` | executable gates |
| `test-driven-development/testing-anti-patterns.md` | descriptive quotes |
| `systematic-debugging/SKILL.md` | executable gates |
| `receiving-code-review/SKILL.md` | mixed; executable gates and descriptive examples |
| `verification-before-completion/SKILL.md` | descriptive history |
| `using-git-worktrees/SKILL.md` | lifecycle; outside debt 0002 |

The TDD gates require human permission for exceptions and send an unknown test strategy
to the human. Systematic debugging sends an uncertain worker to unspecified help and
requires discussion after three failed fixes.
Review-reception stops for clarification or direction on unclear and unverifiable
feedback, on conflicts with prior human decisions, and for architectural escalation; its
example speakers and quoted preferences are descriptive. Verification's single phrase
reports a past loss of trust and is not a gate. Debt 0002 owns only the executable
residuals inside issue #13's explicit test, debugging, review-reception, and verification
boundary.

`using-git-worktrees` is a lifecycle package outside that boundary, not an omitted audit
result. Caller-assigned worktree instructions resolve its creation-consent gate. Its
baseline-failure prompt does not yet return a blocker to a dispatched caller, so
[issue #23][issue-23] owns that separate lifecycle fix under ADR 0005.

## Approaches considered

### Repository license plus canonical-root inventory — selected

Add the exact upstream license once, add a notice that names the source snapshot and all
eleven canonical derived roots, and link both from the README and ADR 0005. Install one
managed copy of the license beside each agent's installed canonical skill tree.

### Per-package license copies

Place a license inside every derived package. This is locally visible but repeats the same
legal text across eleven roots and creates unnecessary drift and review noise.

### Repository-only license

Leave the license under `docs/licenses/` and depend on users retaining the checkout. This
does not cover the installer's normal distribution path, which copies the canonical skill
tree into agent configuration directories without the repository documentation tree.

### Separate vendored source tree

Keep an upstream-shaped mirror and project selected files into `content/skills/`. ADR 0004
defines `content/skills/` as the sole workflow source; a mirror would introduce duplicate
ownership or require a generator that attribution restoration does not need.

### Copy the predecessor debt unchanged

This would retain Claude-only targets and fail to account for the exact canonical tree now
installed to all three agents. A target-owned record instead points to canonical sources
and distinguishes executable gates from descriptive references.

## Design

Create `docs/licenses/superpowers.LICENSE` as a byte-for-byte copy of the upstream
Superpowers 6.1.1 MIT license. Create `docs/licenses/superpowers.md` as the human-readable
notice. It records the upstream project, exact tag and commit, upstream copyright, and MIT
coverage of local modifications; links the license and predecessor provenance; and lists
the eleven canonical covered roots. It also states the covered-root inbound MIT offer and
authority representation.

Add a short README section that points readers to the notice and license rather than
duplicating the inventory, and tells contributors that submitting a covered-root change
offers it under MIT while representing authority to do so. Git history retains the merged
submission. ADR 0005 owns the durable vendoring policy:

- canonical derived packages are maintained forks distributed under MIT;
- updates are deliberate upstream diffs that preserve and review local adaptations;
- re-vendor updates verify license and notice compatibility before importing;
- ADR 0004's exact canonical tree is installed to every supported agent;
- a caller explicitly asserts dispatched mode;
- dispatched gates resolve from written policy or return a blocker, never inferred
  permission; debt 0002 enumerates scoped issue #13 exceptions, while lifecycle exceptions
  remain governed and tracked separately; and
- later shipping skills retain their own push and merge authorization.

ADR 0005 records a narrow exception to ADR 0001 for the canonical license source. Keeping
`docs/licenses/superpowers.LICENSE` beside the notice makes their legal relationship
reviewable while the installer deploys only that named file. It does not establish a
general deployable `docs/` subtree or compete with ADR 0004's canonical skills path.

Extend the existing `install_common_content` entry point in `install.sh`. It installs the
single canonical license source at `licenses/superpowers.LICENSE` under each agent target.
Because the path goes through `install_managed_path`, it participates in existing source
validation, safe-parent handling, drift backup, manifest, and pruning behavior.
`install-test.sh` compares each installed license byte-for-byte with the canonical source,
checks every manifest, and proves drift backup and restoration.

Create debt 0002 for the audited residual TDD, debugging, and review-reception gates and
the descriptive verification reference. It records canonical targets, the all-agent
installation consequence, sanctioned resolution choices, non-regression boundary,
predecessor commit, and a 2026-10-31 review date. Closing issue #13 means the migration is
complete; the record remains open until the adaptations and proofs it names land.

No skill body or installer architecture changes. The canonical directory layout from ADR
0004 remains the source of deployable Agent Skills.

## Failure handling and maintenance

- A missing or altered license is visible as a normal repository diff and fails review;
  the implementation copies the source blob verified against upstream and predecessor
  provenance.
- A missing canonical source makes `install_managed_path` fail with its existing
  actionable missing-source error. Installed drift follows existing backup and replacement
  behavior rather than a license-specific path.
- A future derived canonical root absent from the notice is an incomplete re-vendor change
  under ADR 0005. Its author must update the inventory in the same change.
- If upstream changes license terms or required notices, the re-vendor change first checks
  compatibility with the MIT-only policy. Compatible additional notices are captured with
  the import. An incompatible term or notice stops import until a superseding ADR is
  accepted; the existing snapshot retains the terms already applying to it.
- A future dispatched call into a recorded human gate must return a blocker unless written
  policy fully decides the choice. It may not treat silence as permission.
- Debt 0002's review date bounds re-evaluation even if no upstream refresh occurs; an
  observed skipped or weakened test triggers earlier review.

## Verification

- Resolve annotated tag `v6.1.1` to
  `d884ae04edebef577e82ff7c4e143debd0bbec99`, fetch `LICENSE` by that immutable commit,
  and compare it byte-for-byte with `docs/licenses/superpowers.LICENSE`.
- Enumerate the eleven expected canonical roots from `content/skills/` independently of
  the notice, assert each exists, and exact-diff that set against the notice with no
  missing, extra, substituted, or duplicate roots.
- Run the installer test red before the common license install changes, then green after
  Claude, Codex, and Bob each contain a byte-identical manifest-managed license and the
  drift backup/restoration path passes.
- Sweep the finite canonical issue #13 roots: `test-driven-development`,
  `systematic-debugging`, `receiving-code-review`, and
  `verification-before-completion`. Search every file below those roots case-insensitively
  for `human`, `user`, `ask`, `permission`, `approval`, `discuss`, `clarif`, `partner`,
  `proceed`, `wait`, `stop`, `direction`, `unclear`, and `verify`; inspect each match
  semantically and reconcile it with debt 0002's executable or descriptive classification.
  Confirm lifecycle packages remain explicitly excluded.
- Run the decision-record checker for ADR 0005 and debt 0002.
- Run `just verify`, including skill-layout, public-safety, record, install, shell, and
  workflow checks.
- Review the final diff for host-specific or private material, runtime skill changes, and
  installer changes beyond deploying the one managed license path.

## Scope and decomposition

The operator authorized issue #6 to absorb issue #13 because the general dispatched policy
and its current residual must be reviewed together. The license, notice, installer path,
installer test, README link, ADR, debt record, and design artifacts are one consistency
unit and ship in one pull request that closes both trackers. Runtime skill adaptations
remain deferred to debt 0002. Issue #23 owns the separately discovered lifecycle gate.

[adr-0005]: ../../adr/0005-own-vendored-superpowers-skills.md
[debt-0002]: ../../debt/0002-non-lifecycle-vendored-skills-retain-human-gates.md
[superpowers-611]: https://github.com/obra/superpowers/tree/v6.1.1
[issue-23]: https://github.com/randomparity/agent-config/issues/23
