# Superpowers-derived skill attribution

This repository maintains agent-native forks of selected skills from
[obra/superpowers](https://github.com/obra/superpowers), tag `v6.1.1`, commit
`d884ae04edebef577e82ff7c4e143debd0bbec99`.

Original upstream portions are Copyright (c) 2025 Jesse Vincent and are distributed under
the [MIT license](superpowers.LICENSE). The repository owner confirms that current local
modifications below the covered roots use the same MIT terms.

## Covered roots

Every file below these roots is covered, including local additions and modifications.

### Claude

- `agents/claude/shared/skills/brainstorming/`
- `agents/claude/shared/skills/writing-plans/`
- `agents/claude/shared/skills/executing-plans/`
- `agents/claude/shared/skills/subagent-driven-development/`
- `agents/claude/shared/skills/test-driven-development/`
- `agents/claude/shared/skills/systematic-debugging/`
- `agents/claude/shared/skills/finishing-a-development-branch/`
- `agents/claude/shared/skills/using-git-worktrees/`
- `agents/claude/shared/skills/receiving-code-review/`
- `agents/claude/shared/skills/requesting-code-review/`
- `agents/claude/shared/skills/verification-before-completion/`

### Codex

- `agents/codex/shared/skills/brainstorming/`
- `agents/codex/shared/skills/writing-plans/`
- `agents/codex/shared/skills/executing-plans/`
- `agents/codex/shared/skills/subagent-driven-development/`
- `agents/codex/shared/skills/test-driven-development/`
- `agents/codex/shared/skills/systematic-debugging/`
- `agents/codex/shared/skills/finishing-a-development-branch/`
- `agents/codex/shared/skills/using-git-worktrees/`
- `agents/codex/shared/skills/receiving-code-review/`
- `agents/codex/shared/skills/requesting-code-review/`
- `agents/codex/shared/skills/verification-before-completion/`

### IBM Bob

- `agents/bob/shared/skills/test-driven-development/`
- `agents/bob/shared/skills/verification-before-completion/`

## Contributions and updates

By submitting a change below a covered root, a contributor offers that change under the
canonical MIT terms and represents that they have authority to grant those rights. Git
history retains the merged contribution as evidence. A contribution without that grant
cannot merge.

An upstream refresh is a deliberate re-vendor change. It must record the exact incoming
release and commit, verify compatible license terms and required notices, preserve local
adaptations, and update every applicable projection and this inventory together. An
incompatible term or notice requires a superseding ADR before import.

## Provenance

The predecessor repository recorded the original selection and dispatched lifecycle
adaptation in [ADR 0015](https://github.com/randomparity/claude-config/commit/40570ea3)
and [ADR 0018](https://github.com/randomparity/claude-config/commit/4ab6fdd6).
[ADR 0004](../adr/0004-own-vendored-superpowers-skills.md) is the governing policy in
this repository.
