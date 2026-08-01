# 0004 — Own vendored Superpowers skills as maintained agent projections

## Status

Accepted (2026-07-31)

## Context

This repository publishes agent-native skills for Claude, Codex, and IBM Bob. Some of
those files descend from the MIT-licensed Superpowers 6.1.1 project, but the repository
was imported without the upstream license or a durable inventory of the derived files.
The copies have since diverged by agent syntax and local workflow policy, so neither an
unqualified upstream link nor a claim that the trees are mirrors describes them.

The predecessor repository recorded the original selection in [ADR 0015][predecessor-15]
and the dispatched lifecycle adaptation in [ADR 0018][predecessor-18].
Those records establish provenance, but their Claude-only plugin context does not govern
this repository's multi-agent layout.

## Decision

The repository owns its Superpowers-derived files as maintained forks in the native
agent projections under `agents/<agent>/shared/skills/`. The authoritative attribution
inventory is `docs/licenses/superpowers.md`; it covers every file beneath each listed
root. The unmodified upstream MIT terms are retained at
`docs/licenses/superpowers.LICENSE`.

An upstream update is a deliberate re-vendor change. It records the upstream release or
commit, reviews the upstream diff against local adaptations, updates every applicable
agent projection, and updates the attribution inventory when roots are added or removed.
The projections need not be byte-identical to upstream or to one another. They remain
deployable source owned by this repository under ADR 0001; this decision does not add a
canonical skill tree or a generator.

Interactive behavior remains the default. A caller or orchestrator explicitly asserts
dispatched mode, and that mode flows through downstream lifecycle skills. In dispatched
mode a skill completes its phase and returns to its caller without asking an unavailable
human to choose an integration path and without merging, pushing, or discarding work.
Only skills with such interactive lifecycle edges carry the adaptation. Today those are
`brainstorming`, `writing-plans`, `executing-plans`,
`subagent-driven-development`, and `finishing-a-development-branch` in the Claude and
Codex projections. Bob's current derived skills do not have those edges.

## Consequences

- The public repository carries the upstream copyright and MIT license alongside an
  explicit inventory of every covered projection root.
- Local ownership permits agent-specific syntax and workflow fixes, but every upstream
  refresh is a reviewed merge rather than a blind copy or automatic upgrade.
- A new derived root is incomplete until the attribution inventory covers it; removing a
  root removes its inventory entry in the same change.
- Claude-only plugin settings, namespaces, and deployment assumptions from the
  predecessor records are historical context, not policy here.
- The same skill may legitimately differ across agents, so parity review is semantic and
  scoped to behavior applicable to each agent.

## Considered & rejected

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

[predecessor-15]: https://github.com/randomparity/claude-config/blob/main/docs/adr/0015-vendor-used-skills-drop-overlap-plugins.md
[predecessor-18]: https://github.com/randomparity/claude-config/blob/main/docs/adr/0018-vendored-skills-carry-a-dispatched-mode.md
