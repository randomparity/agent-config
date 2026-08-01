# 0005 — Own vendored Superpowers skills as maintained canonical packages

## Status

Accepted (2026-07-31)

## Context

This repository installs one canonical Agent Skills tree for Claude, Codex, and IBM Bob
under ADR 0004. Eleven packages in that tree descend from the MIT-licensed Superpowers
6.1.1 project at commit `d884ae04edebef577e82ff7c4e143debd0bbec99`, but the public
repository was imported without the upstream license or a durable inventory of the
derived packages. The packages have since diverged from upstream through local workflow
policy, so neither an unqualified upstream link nor a claim that they are mirrors is
accurate.

The predecessor repository recorded the original selection in [ADR 0015][predecessor-15]
and the dispatched lifecycle adaptation in [ADR 0018][predecessor-18]. Those records
establish provenance, but their Claude-only plugin context does not govern this
repository's canonical multi-agent installation model.

## Decision

The repository accepts maintenance responsibility for its Superpowers-derived packages
as maintained forks in the canonical `content/skills/` tree governed by
[ADR 0004][adr-0004]. Original upstream portions retain Jesse Vincent's copyright. The
repository owner confirms that every current local modification in the covered roots is
also licensed under the MIT terms retained at `docs/licenses/superpowers.LICENSE`.

By submitting a future change to a covered root, its contributor offers that change under
the canonical MIT terms and represents that they can grant those rights. The README and
attribution notice publish this rule; the merged contribution retains its evidence. A
change without that grant cannot merge. The authoritative attribution inventory is
`docs/licenses/superpowers.md`; it covers every file beneath each listed canonical root
and records the upstream repository plus the exact tag and commit used as the shared
baseline.

Every repository checkout and installed agent target containing a covered derived skill
carries the upstream copyright and MIT permission notice. The repository keeps one
canonical license source. `install.sh` deploys that source as
`licenses/superpowers.LICENSE` into the Claude, Codex, and Bob configuration targets; it
does not maintain separately editable target copies.

This legal artifact is a narrow exception to [ADR 0001][adr-0001]: its canonical source
remains beside its attribution documentation under `docs/licenses/` even though the
installer deploys it. The exception does not make `docs/` a general payload tree or add a
second provider for an existing deployed path. ADR 0004 continues to own the canonical
skill tree and its installation.

An upstream update is a deliberate re-vendor change. It updates the inventory's exact
release and commit; verifies the applicable upstream license and additional notices; and
imports only material compatible with this MIT-only policy while capturing every required
notice. It reviews the upstream diff against local adaptations, updates each applicable
canonical package, and changes the covered roots when derived packages are added or
removed. An incompatible upstream license or notice requires a superseding decision
before import. The packages need not be byte-identical to upstream, and no generated or
agent-native projection source is introduced.

Interactive behavior remains the default. A caller or orchestrator explicitly asserts
dispatched mode, and that mode flows through downstream derived skills. A dispatched gate
either resolves from the caller's written requirements and repository policy or returns a
blocker to the caller; it never guesses permission from an unavailable human. Debt 0002
enumerates the exceptions inside issue #13's testing, debugging, review-reception, and
verification boundary; it is not an all-skill audit.

The five lifecycle packages carrying embedded dispatched adaptations are `brainstorming`,
`writing-plans`, `executing-plans`, `subagent-driven-development`, and
`finishing-a-development-branch`. They return without merging, pushing, or discarding
work. `using-git-worktrees` is also lifecycle-governed and is explicitly outside debt
0002: caller-assigned worktree instructions resolve its creation-consent gate, while
[issue #23][issue-23] tracks its dispatched baseline-failure gate. This does not restrict
later integration owners such as `ship-pr` and `merge-cleanup`, whose own authorization
governs pushing and merging.

[Debt 0002](../debt/0002-non-lifecycle-vendored-skills-retain-human-gates.md)
owns the remaining human-only gates in the canonical testing, debugging, and
review-reception packages within issue #13's explicit categories, and classifies the
verification reference as descriptive. Because ADR 0004 installs the exact canonical
tree for every supported agent, each executable residual applies to Claude, Codex, and
Bob. Closing issue #13 does not resolve that debt; only the adaptations and proof named by
the record do.

## Consequences

- The public repository carries the upstream copyright and MIT license alongside an
  immutable source baseline and an explicit inventory of eleven canonical package roots.
- Contributors' local modifications in covered roots use the same MIT terms, so a derived
  file does not have split or unstated distribution terms.
- Claude, Codex, and Bob receive the same covered package sources and a managed copy of
  the canonical license through the existing installer manifest and drift-backup path.
- Local maintenance responsibility permits workflow-policy fixes, but every upstream
  refresh is a reviewed merge rather than a blind copy or automatic upgrade.
- A new derived root is incomplete until the attribution inventory covers it; removing a
  root removes its inventory entry in the same change.
- Claude-only plugin settings, namespaces, and deployment assumptions from the
  predecessor records are historical context, not policy here.
- Debt 0002 keeps scoped dispatched-mode gaps visible without duplicating identical debt
  targets for three installed copies of one canonical source.

## Considered & rejected

- **Do nothing, or restore only attribution.** Continued omission leaves the public copies
  without their required notice. Restoring only the notice leaves current maintenance and
  dispatched-mode responsibilities implicit, repeating the provenance loss that exposed
  the omission.
- **Copy the license into every derived package.** This makes each package self-contained
  but creates eleven identical files whose drift obscures which terms are authoritative.
  One canonical license copied into each installed agent target provides the required
  notice without independently maintained package copies.
- **Keep the notice only in the repository checkout.** This leaves the installer
  distributing derived packages without the notice they require. The installer must carry
  the canonical license into each supported target.
- **Apply MIT only to upstream portions.** This leaves local modifications in combined
  derived files under unstated terms. The repository owner confirmed the existing
  modifications use MIT, and future covered contributions must carry the same grant.
- **Restore the predecessor ADRs verbatim.** They explain the first vendoring decision,
  but their plugin and Claude-only assumptions are false for this repository. Linking
  them as provenance preserves history without importing obsolete policy.
- **Keep exact upstream mirrors and put adaptations elsewhere.** The lifecycle changes
  must be encountered at the gates they alter, and the canonical packages already carry
  local workflow policy. Separating adaptations would make an installed package
  incomplete on its own.
- **Add a second vendored source tree.** ADR 0004 already establishes `content/skills/` as
  the only repository-owned workflow source. A mirror would reintroduce duplicate sources
  or require a generator without improving attribution.
- **Split dispatched behavior into a separate ADR.** Licensing, updates, and local
  adaptations are one maintained-fork policy required by issue #6. Debt 0002 gives the
  independently changing residual gates their own lifecycle.

[adr-0001]: 0001-canonical-content-agent-native-projections.md
[adr-0004]: 0004-canonical-agent-skills.md
[predecessor-15]: https://github.com/randomparity/claude-config/commit/40570ea3
[predecessor-18]: https://github.com/randomparity/claude-config/commit/4ab6fdd6
[issue-23]: https://github.com/randomparity/agent-config/issues/23
