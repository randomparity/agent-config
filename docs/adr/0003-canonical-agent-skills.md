# 0003. Canonical Agent Skills Across Supported Agents

## Status

Accepted

## Context

The repository currently owns workflow skills independently under the Claude,
Codex, and Bob native payloads. The inventories already drift: Codex has the
complete workflow set, Claude has a smaller mixture of skills and legacy custom
commands, and Bob has only two skills.

Claude Code, Codex, and IBM Bob now consume the open Agent Skills directory
format: a skill directory containing `SKILL.md` plus optional supporting files.
Claude custom commands and skills also provide the same invocation surface, so
keeping command copies no longer provides a distinct capability.

ADR 0001 assigns skill adapters and ambiguous deployed paths to native payloads
until a renderer defines precedence. It did not account for a workflow format
that all supported agents share. This decision supersedes ADR 0001 only for
Agent Skills ownership and precedence; ADR 0001 continues to govern native
settings, instructions, modes, MCP files, and other agent-specific formats.

## Decision

Own every reusable workflow skill once under `content/skills/`. Install that
tree byte-for-byte as `skills/` for Claude, Codex, and Bob. Remove per-agent
skill trees and Claude custom-command copies.

The portable contract is the required open Agent Skills subset: a directory
whose `SKILL.md` has matching `name` and non-empty `description` fields, uses
relative bundled-resource paths, and does not require behavior-bearing vendor
frontmatter. A skill may require an external product or capability only when it
names that requirement and stops actionably when the host cannot provide it.

Keep agent-specific settings, instruction roots, modes, MCP configuration, and
other formats under `agents/<agent>/shared/`. A canonical skill may contain an
optional vendor metadata file when it does not change the shared workflow;
clients that do not understand that optional file ignore it.

An invocable workflow artifact is a `SKILL.md` or a file under a client command
directory. Native instruction and mode files may reference skills or define
durable client policy, but they are not alternate implementations of a named
workflow. Add a repository guard that rejects any invocable workflow artifact
under `agents/`. Installation tests compare every deployed skill tree with the
canonical source, so a missing, extra, or changed file fails verification.

Exact-copy tests prove source and inventory coordination, not identical model
behavior. Verification also validates the portable subset and smoke-tests skill
discovery and safe invocation in every supported client available on the test
host. An unavailable proprietary client is reported as an unrun arm. Client
version floors remain outside this installer because it does not install or
upgrade the clients themselves.

## Consequences

- A workflow edit has one source and reaches all supported agents on the next
  install.
- Claude retains direct slash invocation through its skill interface without a
  parallel command source.
- Agent-specific prose inside a shared skill must be either generalized or
  explicitly scoped to an optional external capability such as Codex Fleet.
- Vendor releases may still change discovery or model behavior independently;
  byte identity prevents repository drift but cannot prevent vendor drift.
- Adding a client that supports Agent Skills requires only an installer target
  and an exact-copy test; it does not create a new workflow projection.
- Existing manifests prune removed Claude commands during reinstall and replace
  each previously managed per-agent skill tree with the canonical tree.

## Considered & Rejected

- Generate native skill projections from templates. Rejected because all three
  clients already accept the same directory format; a renderer would add a
  transformation layer without adding compatibility.
- Keep per-agent skill sources and compare or regenerate them in CI. Rejected
  because duplicated checked-in outputs remain competing ownership surfaces and
  invite agent-only edits.
- Install the Codex tree into Bob and leave Claude separate. Rejected because it
  fixes one missing copy while preserving the drift mechanism that caused the
  issue.
- Keep the current layout and manually synchronize it. Rejected because the
  current inventory proves manual coordination does not hold.
