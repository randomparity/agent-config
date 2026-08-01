# 0004 — Canonical Agent Skills Across Supported Agents

## Status

Accepted (2026-07-31)

## Context

The repository previously stored reusable workflows independently under the
Claude, Codex, and Bob native payloads. Their inventories drifted: Codex had the
complete set, Claude had a mixture of skills and legacy commands, and Bob had two
skills.

All three supported clients consume Agent Skills directories containing a
`SKILL.md` file plus optional resources. Maintaining separate implementations no
longer provides a useful adapter boundary.

This decision supersedes ADR 0001 only for Agent Skills ownership. ADR 0001
continues to govern settings, root instructions, modes, MCP files, and other
agent-specific formats.

## Decision

Own every reusable workflow once under `content/skills/`. Install that exact tree
as `skills/` for Claude, Codex, and Bob. Remove native skill trees and Claude
command copies from `agents/<agent>/shared/`.

Canonical packages use a portable Agent Skills subset:

- each immediate directory contains `SKILL.md`;
- frontmatter contains only a matching `name` and a JSON-quoted `description`;
- names and paths use a portable ASCII subset and avoid documented client command
  collisions;
- packages contain only regular files and directories, with no symlinks; and
- shared workflow instructions do not depend on an installed client config root.

Repository verification rejects native workflow sources and malformed canonical
packages. Installer tests deploy every supported client into temporary roots and
compare each installed skill tree with `content/skills/`, including executable
file modes.

The existing installer remains a sequential managed-path installer. It preserves
its current timestamped drift backups and newline manifest used to prune paths it
previously managed. Installing `all` is not a distributed transaction: a failure
may leave some clients updated before others, and rerunning the installer is the
reconciliation path.

## Consequences

- A workflow edit has one repository source and one review surface.
- Claude, Codex, and Bob receive the same checked-in workflow inventory.
- Adding a native skill or command copy fails verification.
- Vendor discovery and model behavior may still differ; this repository controls
  installed workflow files, not client releases.
- The installer does not add locks, journals, repair commands, historical
  ownership ledgers, or cross-filesystem rollback machinery.

## Considered & rejected

- **Keep per-agent copies.** This is the drift mechanism issue 17 reported.
- **Generate native projections.** All clients already accept the shared format,
  so a renderer would add another representation without adding capability.
- **Cross-client transaction protocol.** Atomic promotion, durable recovery, and
  repair state are disproportionate to a local configuration installer. The
  current operation is idempotent and can be rerun.
