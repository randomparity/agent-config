# 0001 — Canonical Content With Agent-Native Projections

## Status

Accepted (2026-07-31)

## Context

The unified config repository must serve Claude Code, Codex, and IBM Bob while
remaining public-safe. The existing Claude and Codex repositories share many
workflow concepts, but their native config surfaces differ:

- Claude uses `CLAUDE.md`, JSON settings, slash-command markdown front matter,
  optional agents, skills, hooks, plugins, and CLI-managed MCP registration.
- Codex uses `AGENTS.md`, TOML settings, and skills as workflow entry points.
- Bob uses `AGENTS.md`, `.bob/skills`, `.bob/custom_modes.yaml`, `.bob/rules`,
  `.bob/mcp.json`, and mode tool groups.

Some content can be common prose. Other content has to name native invocation
syntax, config paths, metadata, permissions, or tool groups.

## Decision

Keep agent-neutral content under `content/`, and keep deployable native payloads
under `agents/<agent>/shared/`.

Canonical content owns neutral subtrees such as language and orchestration
references. Agent-native payloads own root instruction files, settings, command
metadata, skill adapters, modes, MCP files, and any path whose meaning differs by
agent. If both areas could plausibly provide the same deployed path, the native
payload owns it until a later ADR introduces a renderer with an explicit
precedence rule.

The installer deploys canonical content into each target only for those neutral
subtrees, and deploys agent-native payloads where the tools require different
formats or semantics. Host overlays are not stored in this public repository;
the installer reads optional private overlays from a local directory outside the
repo.

## Consequences

- The repo avoids pretending that incompatible agent formats are one artifact.
- Shared standards and references have one canonical home where their deployed
  path is not agent-specific.
- Agent-native payloads can still be reviewed and installed without a build step
  that rewrites every command or skill.
- Some duplication remains where behavior is shared but invocation syntax is
  native. That duplication is intentional until a proven renderer removes more
  complexity than it adds.
- Public-safety verification becomes part of the contract because the installer
  can read private overlays while the repo remains public.

## Considered & rejected

- Single shared tree copied to every agent. Rejected because Claude commands,
  Codex skills, and Bob modes use incompatible metadata and invocation models.
  A lowest-common-denominator tree would either break native behavior or hide
  agent-specific assumptions in prose.
- Separate repositories for each agent. Rejected because it preserves the
  current drift problem and makes shared workflow changes require repeated
  manual edits.
- Fully generated native payloads from templates on day one. Rejected for the
  initial repo setup because it would add a fragile transformation layer before
  the stable boundaries are proven. The chosen layout leaves room for targeted
  renderers later.
