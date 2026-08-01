# 0004 — Own vendored Superpowers skills as maintained agent projections

## Status

Accepted (2026-07-31)

## Context

This repository publishes agent-native skills for Claude, Codex, and IBM Bob. Some of
those files descend from the MIT-licensed Superpowers 6.1.1 project at commit
`d884ae04edebef577e82ff7c4e143debd0bbec99`, but the repository was imported without the
upstream license or a durable inventory of the derived files. The copies have since
diverged by agent syntax and local workflow policy, so neither an unqualified upstream
link nor a claim that the trees are mirrors describes them.

The predecessor repository recorded the original selection in [ADR 0015][predecessor-15]
and the dispatched lifecycle adaptation in [ADR 0018][predecessor-18]. Those records
establish provenance, but their Claude-only plugin context does not govern this
repository's multi-agent layout.

## Decision

The repository accepts maintenance responsibility for its Superpowers-derived files as
maintained forks in the native agent projections under `agents/<agent>/shared/skills/`.
Original upstream portions retain Jesse Vincent's copyright. The repository owner
confirms that every current local modification in the covered roots is also licensed
under the MIT terms retained at `docs/licenses/superpowers.LICENSE`. By submitting a
future change to a covered root, its contributor offers that change under the canonical
MIT terms and represents that they can grant those rights. The README and attribution
notice publish this rule; the merged contribution retains its evidence. A change without
that grant cannot merge. The authoritative attribution inventory is
`docs/licenses/superpowers.md`; it covers every file beneath each listed root and records
the canonical upstream repository plus the exact tag and commit used as the shared
baseline.

Every repository checkout and installed agent projection containing a covered derived
skill carries the upstream copyright and MIT permission notice. The repository keeps one
canonical license source. `install.sh` deploys that source as
`licenses/superpowers.LICENSE` into the Claude, Codex, and Bob configuration targets; it
does not maintain separately editable projection copies.

This legal artifact is a narrow exception to [ADR 0001][adr-0001]: the canonical source
remains beside its attribution documentation under `docs/licenses/` even though the
installer deploys it. The exception does not make `docs/` a general payload tree, add a
second provider for an existing deployed path, or change agent-native projection
ownership. It keeps the permission text and the inventory explaining its coverage in one
reviewable location.

An upstream update is a deliberate re-vendor change. It updates the inventory's exact
release and commit; verifies the applicable upstream license and additional notices; and
imports only material compatible with this MIT-only policy while capturing every required
notice. It then reviews the upstream diff against local adaptations, updates every
applicable agent projection, and changes the covered roots when skills are added or
removed. An incompatible upstream license or notice requires a superseding decision
before import. The projections need not be byte-identical to upstream or to one another.
They remain deployable source maintained by this repository under ADR 0001; this decision
does not add a canonical skill tree or a generator.

Interactive behavior remains the default. A caller or orchestrator explicitly asserts
dispatched mode, and that mode flows through downstream derived skills. The target and
non-regression rule is that a dispatched gate either resolves from the caller's written
requirements and repository policy or returns a blocker to the caller; it never guesses
permission from an unavailable human. Debt 0002 enumerates the current exceptions inside
issue #13's testing, debugging, review-reception, and verification boundary; it is not an
all-skill audit. The five Claude and Codex lifecycle skills carrying embedded lifecycle
adaptations are `brainstorming`, `writing-plans`, `executing-plans`,
`subagent-driven-development`, and `finishing-a-development-branch`. They return without
merging, pushing, or discarding work. `using-git-worktrees` is also lifecycle-governed and
is explicitly outside debt 0002: caller-assigned worktree instructions resolve its
creation-consent gate, while [issue #23][issue-23] tracks its dispatched baseline-failure
gate. This does not restrict later, non-vendored integration owners such as `ship-pr` and
`merge-cleanup`, whose own authorization governs pushing and merging.

[Debt 0002](../debt/0002-non-lifecycle-vendored-skills-retain-human-gates.md)
owns the remaining human-only gates in the derived testing, debugging, and review-reception
skills within issue #13's explicit acceptance categories, and classifies verification's
audited reference as descriptive. It records which projections deploy each scoped skill
and which scoped references are executable or descriptive. Closing its tracker does not
resolve that debt; only the adaptations and proof named by the record do.

## Consequences

- The public repository carries the upstream copyright and MIT license alongside an
  immutable source baseline and an explicit inventory of every covered projection root.
- Contributors' local modifications in the covered roots use the same MIT terms, so a
  derived file does not have split or unstated distribution terms.
- Installed projections carry a managed copy of the canonical license. A license update
  flows through the existing installer manifest and drift-backup behavior.
- Local maintenance responsibility permits agent-specific syntax and workflow fixes, but
  every upstream refresh is a reviewed merge rather than a blind copy or automatic
  upgrade.
- A new derived root is incomplete until the attribution inventory covers it; removing a
  root removes its inventory entry in the same change.
- Claude-only plugin settings, namespaces, and deployment assumptions from the
  predecessor records are historical context, not policy here.
- The same skill may legitimately differ across agents, so parity review is semantic and
  scoped to behavior applicable to each agent.
- Debt 0002 keeps current dispatched-mode gaps visible without pretending Bob deploys
  skills that exist only in the Claude and Codex projections.

## Considered & rejected

- **Do nothing, or restore only attribution.** Continued omission leaves the public copies
  without their required notice. Restoring only the notice leaves current maintenance and
  dispatched-mode responsibilities implicit, repeating the provenance loss that exposed
  the omission.
- **Copy the license into every skill directory.** This makes each subtree self-contained
  but creates many identical files whose drift obscures which terms are authoritative.
  One canonical license copied into each installed agent target provides the required
  notice without one independently maintained copy per skill.
- **Keep the notice only in the repository checkout.** This leaves the normal installer
  distributing derived skill copies without the notice they require. The installer must
  carry the canonical license into each applicable target.
- **Apply MIT only to upstream portions.** This avoids an inbound rule but leaves local
  modifications in combined derived files under unstated terms. The repository owner
  confirmed the existing modifications use MIT, and future covered contributions must
  carry the same grant.
- **Restore the predecessor ADRs verbatim.** They explain the first vendoring decision,
  but their plugin and Claude-only deployment assumptions are false for this repository.
  Linking them as provenance preserves history without importing obsolete policy.
- **Keep exact upstream mirrors and put adaptations elsewhere.** The lifecycle changes
  must be encountered at the gates they alter, and agent-native syntax already differs.
  Separating adaptations would make the deployed skill incomplete on its own.
- **Create one canonical skill tree and generate all projections.** That could reduce
  repetition, but it changes ADR 0001's ownership and installation model. Attribution
  restoration does not justify a new renderer or generated-artifact contract.
- **Split dispatched behavior into a separate ADR.** Licensing, updates, and local
  adaptations are one maintained-fork policy required by issue #6. Debt 0002 already
  gives the independently changing residual gates their own lifecycle without making the
  governing re-vendor decision ambiguous.

[adr-0001]: 0001-canonical-content-agent-native-projections.md
[predecessor-15]: https://github.com/randomparity/claude-config/commit/40570ea3
[predecessor-18]: https://github.com/randomparity/claude-config/commit/4ab6fdd6
[issue-23]: https://github.com/randomparity/agent-config/issues/23
