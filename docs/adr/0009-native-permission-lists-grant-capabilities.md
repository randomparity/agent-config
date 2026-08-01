# 0009 — Native permission lists grant capabilities

## Status

Accepted (2026-08-01)

## Context

An allowlist can be mistaken for a complete list of what an agent may do. On supported
agent-native surfaces that treat listed entries as grants, that reading reverses the
safety meaning: adding an entry widens what proceeds without another permission decision;
omitting an entry does not necessarily make the capability unavailable.

This adapts the predecessor repository's [`allowed-tools` decision][predecessor] to the
configuration surfaces actually supported here. The canonical `content/skills/` subset
permits only `name` and `description` frontmatter, so it has no shared `allowed-tools`
policy. Codex's checked-in `config.base.toml` likewise defines no permission allowlist.
IBM Bob custom-mode `groups` controls available tool groups and is restrictive when a
group is absent, so it is explicitly outside this grant-only rule. Unsupported parity
must not be inferred from this record.

## Decision

Treat native allowlists as grants only on the agent and field whose native semantics say
they grant. For Claude Code, `permissions.allow` entries pre-authorize matching operations.
Their absence is not a deny; `permissions.deny` is the checked-in restrictive surface.
Private Claude settings overlays may add `permissions.allow`, so this distinction applies
even though the public base currently contains only deny rules.

Review every added or broadened entry as a widened grant and use the agent's native
restrictive mechanism when a capability must be unavailable. Do not translate this rule
onto IBM Bob custom-mode `groups`, Codex approval or sandbox settings, Claude
`permissions.deny`, canonical skill frontmatter, or any field whose native contract has
different semantics.

## Consequences

- A short allowlist is not described as a sandbox, and a missing entry is not evidence of
  prohibition.
- Adding Claude allow rules or Bob groups is a permission change requiring security-aware
  review even when it appears to make configuration more explicit.
- Claude's current shared settings continue to use `permissions.deny`; this record does not
  convert denies into grants or add an allowlist.
- Bob's `agent-config-maintainer` mode retains its existing restrictive group selection.
- Bob, Codex, and the portable skill format gain no phantom permission parity.

## Considered & rejected

- **Call every native permission list restrictive.** The label "allowlist" does not
  override the implementing agent's semantics and would invert review of widened grants.
- **Apply the grant rule to Bob custom-mode groups.** Bob documents omitted groups as
  unavailable to the mode, so doing so would erase a real restriction.
- **Declare one cross-agent permission schema.** Claude, Codex, and Bob expose different
  controls; a synthetic common model would document behavior the repository cannot enforce.
- **Add allow fields for symmetry.** Empty or speculative configuration adds surface
  without a current need and could change prompts or capability access.
- **Record only the predecessor's Claude command field.** This repository intentionally
  excludes that field from canonical skill frontmatter and owns different native
  permission surfaces; copying the old scope would be inaccurate.

[predecessor]: https://github.com/randomparity/claude-config/blob/main/docs/adr/0017-allowed-tools-grants-it-never-restricts.md
