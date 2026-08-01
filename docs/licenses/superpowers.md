# Superpowers-derived skill attribution

This repository maintains canonical Agent Skills forks of selected packages from
[obra/superpowers](https://github.com/obra/superpowers), tag `v6.1.1`, commit
`d884ae04edebef577e82ff7c4e143debd0bbec99`.

Original upstream portions are Copyright (c) 2025 Jesse Vincent and are distributed under
the [MIT license](superpowers.LICENSE). The repository owner confirms that current local
modifications below the covered roots use the same MIT terms.

## Covered roots

Every file below these canonical roots is covered, including local additions and
modifications:

- `content/skills/brainstorming/`
- `content/skills/writing-plans/`
- `content/skills/executing-plans/`
- `content/skills/subagent-driven-development/`
- `content/skills/test-driven-development/`
- `content/skills/systematic-debugging/`
- `content/skills/finishing-a-development-branch/`
- `content/skills/using-git-worktrees/`
- `content/skills/receiving-code-review/`
- `content/skills/requesting-code-review/`
- `content/skills/verification-before-completion/`

The installer copies the canonical skill tree to Claude, Codex, and IBM Bob and installs
the canonical license as `licenses/superpowers.LICENSE` in each target. Those installed
copies are outputs of the covered roots, not independently maintained sources.

## Contributions and updates

By submitting a change below a covered root, a contributor offers that change under the
canonical MIT terms and represents that they have authority to grant those rights. Git
history retains the merged contribution as evidence. A contribution without that grant
cannot merge.

An upstream refresh is a deliberate re-vendor change. It must record the exact incoming
release and commit, verify compatible license terms and required notices, preserve local
adaptations, and update every applicable canonical package and this inventory together.
An incompatible term or notice requires a superseding ADR before import.

## Provenance

The predecessor repository recorded the original selection and dispatched lifecycle
adaptation in [ADR 0015](https://github.com/randomparity/claude-config/commit/40570ea3)
and [ADR 0018](https://github.com/randomparity/claude-config/commit/4ab6fdd6).
[ADR 0005](../adr/0005-own-vendored-superpowers-skills.md) is the governing vendoring
policy in this repository; [ADR 0004](../adr/0004-canonical-agent-skills.md) owns the
canonical multi-agent skill layout.
