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
Original upstream portions retain Jesse Vincent's copyright. The combined derived files,
including local modifications by this repository's contributors, are distributed under
the MIT terms retained at `docs/licenses/superpowers.LICENSE`. The authoritative
attribution inventory is `docs/licenses/superpowers.md`; it covers every file beneath
each listed root and records the canonical upstream repository plus the exact tag and
commit used as the shared baseline.

An upstream update is a deliberate re-vendor change. It updates the inventory's exact
release and commit, reviews the upstream diff against local adaptations, updates every
applicable agent projection, and changes the covered roots when skills are added or
removed. The projections need not be byte-identical to upstream or to one another. They
remain deployable source maintained by this repository under ADR 0001; this decision does
not add a canonical skill tree or a generator.

Interactive behavior remains the default. A caller or orchestrator explicitly asserts
dispatched mode, and that mode flows through downstream derived skills. A dispatched gate
either resolves from the caller's written requirements and repository policy or returns a
blocker to the caller; it never guesses permission from an unavailable human. The five
Claude and Codex lifecycle skills with embedded adaptations are `brainstorming`,
`writing-plans`, `executing-plans`, `subagent-driven-development`, and
`finishing-a-development-branch`. They return without merging, pushing, or discarding
work. This does not restrict later, non-vendored integration owners such as `ship-pr` and
`merge-cleanup`, whose own authorization governs pushing and merging.

[Debt 0002](../debt/0002-non-lifecycle-vendored-skills-retain-human-gates.md)
owns the remaining human-only gates in derived testing, debugging, and review-reception
skills. It records which projections deploy each skill, which references are executable
gates, and which are descriptive. Closing its tracker does not resolve that debt; only the
adaptations and proof named by the record do.

## Consequences

- The public repository carries the upstream copyright and MIT license alongside an
  immutable source baseline and an explicit inventory of every covered projection root.
- Contributors' local modifications in the covered roots use the same MIT terms, so a
  derived file does not have split or unstated distribution terms.
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
  One license plus an explicit root inventory provides the required notice without that
  duplication.
- **Restore the predecessor ADRs verbatim.** They explain the first vendoring decision,
  but their plugin and Claude-only deployment assumptions are false for this repository.
  Linking them as provenance preserves history without importing obsolete policy.
- **Keep exact upstream mirrors and put adaptations elsewhere.** The lifecycle changes
  must be encountered at the gates they alter, and agent-native syntax already differs.
  Separating adaptations would make the deployed skill incomplete on its own.
- **Create one canonical skill tree and generate all projections.** That could reduce
  repetition, but it changes ADR 0001's ownership and installation model. Attribution
  restoration does not justify a new renderer or generated-artifact contract.

[predecessor-15]: https://github.com/randomparity/claude-config/commit/40570ea3
[predecessor-18]: https://github.com/randomparity/claude-config/commit/4ab6fdd6
