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

Own every reusable workflow skill once under `content/skills/`. Install every
canonical directory under `skills/` for Claude, Codex, and Bob with identical
file content, file type, and executable mode. Canonical skills contain no
symlinks. Remove per-agent skill trees and Claude custom-command copies.

The portable contract is the required open Agent Skills subset: a directory
whose `SKILL.md` has matching `name` and non-empty `description` fields, uses
relative bundled-resource paths, never names a supported client's installed
config root, and does not require behavior-bearing vendor frontmatter. Target
repository paths remain repository-relative. A skill may require an external
product or capability only when it names that requirement and stops actionably
when the host cannot provide it.

Keep agent-specific settings, instruction roots, modes, MCP configuration, and
other formats under `agents/<agent>/shared/`. A canonical skill may contain an
optional vendor metadata file when it does not change the shared workflow;
clients that do not understand that optional file ignore it.

An invocable workflow artifact is a `SKILL.md` or a file under a client command
directory. Native instruction and mode files may reference skills or define
durable client policy, but they are not alternate implementations of a named
workflow. Add a repository guard that rejects any invocable workflow artifact
under `agents/`. Installation tests compare every deployed skill tree with the
canonical source, so missing or extra files and content, type, link, or
executable-mode changes fail verification.

Exact-copy tests prove source and inventory coordination, not identical model
behavior. Verification also validates the portable subset and smoke-tests skill
discovery and safe invocation in every supported client available on the test
host. An unavailable proprietary client is reported as an unrun arm. Client
version floors remain outside this installer because it does not install or
upgrade the clients themselves.

The installer owns each canonical skill name, not the complete user-level
`skills/` destination. It preserves unrelated user-installed skill directories,
backs up managed-name drift before replacement, and verifies every managed
directory against the canonical source. A same-name skill or legacy Claude
command that is not in the old manifest is a collision and stops with an
actionable error rather than silently deleting user content. Managed legacy
commands are backed up and pruned. Project, enterprise, plugin, and other
higher- or lower-precedence skill scopes remain outside this user-level
installer.

Names owned by the previous manifest but absent from the canonical inventory
remain managed removals. The installer backs them up, prunes them from every
selected client in the same transaction as additions and updates, and restores
them if that transaction rolls back.

Shared-skill installation is a transaction across the selected clients. The
installer validates and stages every canonical skill before changing a live
destination, promotes staged directories atomically within each destination,
then validates all selected clients. A promotion or validation failure restores
every changed skill directory; a rollback failure reports the inconsistent
destinations explicitly and leaves the transaction record and lock in a
needs-repair state. No later install proceeds until the operator restores the
named paths or makes rollback possible. This transaction applies to
`--agent all` and to a single selected client.

Before recovery or staging, the installer acquires one exclusive lock under the
private agent-config root and holds it through commit, rollback, and cleanup. A
competing installer stops actionably. A dead same-host lock may be taken over
only after consulting the transaction record; an owner on another host requires
operator intervention.

Before the first promotion, the installer writes a mode-`0600` transaction
record under the private root, outside this repository. The record identifies
selected destinations plus stage, backup, promotion, removal, manifest, commit,
and cleanup state without storing configuration content. Each live rename uses
write-ahead ordering: first persist `promotion-pending` or `removal-pending`,
then rename, then persist completion. Recovery treats a pending operation as
possibly applied and restores it idempotently from its recorded backup.

After all destinations validate, the installer atomically publishes every new
ownership manifest and marks the transaction committed. Recovery rolls back
only an uncommitted record. A committed record resumes transaction-backup
cleanup idempotently and never restores the old revision. The record is cleared
and the lock released only after cleanup succeeds.

## Consequences

- A workflow edit has one source and reaches all supported agents on the next
  install.
- Claude retains direct slash invocation through its skill interface without a
  parallel command source.
- Agent-specific prose inside a shared skill must be either generalized or
  explicitly scoped to an optional external capability such as Codex Fleet.
- Vendor releases may still change discovery or model behavior independently;
  byte identity prevents repository drift but cannot prevent vendor drift.
- “Supported” in this repository means that current vendor documentation
  accepts the portable package and the installer deploys it correctly. It does
  not promise identical model behavior or own a client release lifecycle.
- Ordinary install errors and process interruption are recoverable from the
  transaction record. Storage, permission, or backup failures can still prevent
  rollback and leave live clients inconsistent; the installer detects and names
  that operator-repair state but cannot make an unwritable filesystem atomic.
- Adding a client that supports Agent Skills requires an installer target,
  portable-contract validation, an exact-copy test for every managed name, and
  a discovery/safe-invocation smoke-test arm. It does not create a new workflow
  projection.
- Existing manifests prune removed Claude commands during reinstall and replace
  each previously managed per-agent skill with its canonical directory while
  preserving unrelated user skills.
- Removing or renaming a canonical skill removes the old managed name from all
  selected clients transactionally; its backup remains available under the
  installer's timestamped backup tree.

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
