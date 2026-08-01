# 0008 — Copy managed agent configuration

## Status

Accepted (2026-08-01)

## Context

The unified installer deploys shared configuration for Claude Code, Codex, and IBM Bob.
Linking a destination back to the checkout would make uncommitted edits, partial writes,
and branch switches live in running agents. Copying avoids that coupling, but copied files
can drift and removed sources can remain active unless the installer owns their lifecycle.

This adapts the predecessor repository's [copy-deployment decision][predecessor] to one
installer and three supported agents. The target repository uses per-agent configuration
roots, `.agent-config-manifest`, and `.agent-config-backups` rather than the predecessor's
Claude-only paths and names.

## Decision

`install.sh` deploys every managed file and directory by copy for all supported agents.
Repository edits remain inert until the installer runs. Before replacing a destination
whose contents or executable modes differ, the installer preserves it under the agent
root's timestamped `.agent-config-backups/<timestamp>/drift/` tree.

The prior `.agent-config-manifest` is the only authority to prune a path no longer in the
new managed set. A pruned path is backed up under the corresponding `pruned/` tree before
removal; an unmanifested path is never pruned. The installer validates managed relative
paths and refuses both writes and removals through symlinked destination ancestors. It
replaces a managed-path symlink itself instead of following it.

The manifest is replaced only after managed copies and pruning succeed. A failed run may
leave some copied paths updated, but it retains the prior pruning authority; rerunning the
sequential installer is the reconciliation path.

## Consequences

- Feature branches, worktrees, and partial repository edits cannot mutate installed config.
- Pulling repository changes does not deploy them; each host must rerun `install.sh`.
- Intentional destination edits are overwritten, with a recoverable drift backup.
- Only previously manifested paths can be removed automatically, so stale unmanifested
  artifacts require manual cleanup.
- `--agent all` remains sequential rather than transactional across agent roots.

## Considered & rejected

- **Symlink managed paths into the checkout.** This restores immediate updates but also
  restores live coupling to unreviewed edits and branch switches.
- **Copy without a manifest.** This cannot safely distinguish stale managed files from
  user- or tool-owned files, so it either leaves active stale config or risks data loss.
- **Sweep every unrecognized destination path.** Agent roots contain runtime and private
  state outside this repository's ownership; absence from the source tree is not deletion
  authority.
- **Stop for confirmation on drift.** Interactive deployment would make unattended host
  reconciliation unreliable; backup followed by replacement preserves recoverability.
- **Make multi-agent installation transactional.** Locks, journals, and cross-root rollback
  add machinery disproportionate to local configuration that can be reconciled by rerun.

[predecessor]: https://github.com/randomparity/claude-config/blob/main/docs/adr/0011-config-deploys-by-copy-not-symlink.md
