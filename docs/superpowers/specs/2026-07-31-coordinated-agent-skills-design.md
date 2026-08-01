# Coordinated Agent Skills Design

## Purpose

Issue 17 reports that installing IBM Bob provides only two skills while Codex
has the complete workflow set. Repository-owned workflows must have one source
and must be installed consistently for Claude Code, Codex, and IBM Bob.

This design coordinates the files the repository owns. It does not attempt to
make independent client releases behave identically or turn the local installer
into a distributed transaction manager.

## Scope

In scope:

- one canonical Agent Skills tree;
- the same installed workflow inventory for all supported agents;
- removal and prevention of agent-native workflow copies;
- a portable structural guard; and
- exact-copy installation tests, including executable modes.

Out of scope:

- cross-client locks, journals, atomic commit, or rollback;
- crash/reboot reconstruction or repair commands;
- version-2 manifests and historical ownership ledgers;
- immutable source snapshots and filesystem-topology restrictions; and
- live-model behavioral grading.

## Canonical ownership

`content/skills/` is the only repository-owned invocable workflow source. Each
immediate child is one skill package. The initial inventory is the former Codex
superset because it contained all existing workflows.

The canonical inventory currently contains 35 skills. `simplify` was renamed to
`simplify-changes` because Claude documents `/simplify` as a bundled command. All
repository-owned cross-skill references use the canonical name.

No `SKILL.md`, `skills/` tree, or command directory may exist under `agents/`.
Agent-native settings, root instructions, Bob modes, MCP configuration, rules,
and other non-workflow formats remain under `agents/<agent>/shared/`.

## Portable package contract

Each canonical skill:

1. is an immediate directory under `content/skills/`;
2. contains a regular `SKILL.md` file;
3. begins with exactly these four frontmatter lines:

   ```text
   ---
   name: <directory-name>
   description: "<one-line JSON string>"
   ---
   ```

4. has non-empty Markdown after the frontmatter;
5. uses a name of 1–64 lowercase ASCII letters, digits, or hyphens, without a
   leading, trailing, or consecutive hyphen;
6. does not use a name in `scripts/reserved-skill-names.txt`;
7. contains only regular files and directories, not symlinks or special files;
8. uses portable ASCII path components no longer than 100 bytes, complete paths
   no longer than 512 bytes, no trailing dots, and no ASCII case-fold collision;
   and
9. does not name `~/.claude`, `~/.codex`, `~/.bob`, or equivalent `$HOME` roots
   as its installed execution root.

Executable file modes are meaningful and must survive installation. Supporting
resources remain relative to their skill package. The guard deliberately does
not implement a Markdown parser or validate every link syntax.

## Installation

The existing command remains:

```text
./install.sh --agent claude|codex|bob|all
```

Each agent maps the same source:

```text
content/skills -> <agent-config-dir>/skills
```

The installer retains its existing managed-path behavior:

- compare source and destination content plus executable-file paths;
- back up a changed managed path under `.agent-config-backups/`;
- replace the managed path with `cp -pR`;
- record managed paths in `.agent-config-manifest`; and
- prune paths named by the previous manifest but absent from the new manifest.

This change does not alter private-overlay handling, native settings merges, Bob
dual-path settings/MCP writes, or opt-in Claude MCP registration.

`--agent all` installs clients sequentially. If an install stops partway through,
the operator reruns the same command after correcting the reported error. The
single canonical source and idempotent reinstall converge the clients without a
new recovery protocol.

## Repository guard

`scripts/check-skill-layout.sh` runs through `just skills-check` and `just verify`.
It fails when:

- a workflow source or symlink appears under `agents/`;
- a canonical package violates the frontmatter, name, path, or file-type rules;
- a canonical name collides with the checked-in reserved-name inventory; or
- shared workflow text names a supported client's installed config root.

The reserved-name file records source URLs and retrieval dates. A newly observed
vendor collision requires updating the inventory and renaming the canonical
workflow before installation.

## Verification

`scripts/check-skill-layout-test.sh` exercises the structural rules with temporary
fixtures. `install-test.sh` installs all three agents into temporary roots and
asserts:

- every destination skill tree is byte-for-byte equal to `content/skills/`;
- executable-file paths match the canonical tree;
- all 35 canonical skills are present, including `simplify-changes`;
- the reserved `simplify` name is absent;
- executable-mode drift is repaired on reinstall; and
- existing managed-path pruning, runtime-state preservation, overlays, and drift
  backups continue to work.

`just verify` remains the completion gate.

## Rollback

Before merge, revert the branch commits. After release, revert the change and run
the restored installer again. Timestamped backups created by the existing
installer remain available for operator recovery; no new recovery format is
introduced.
