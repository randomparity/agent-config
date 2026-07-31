# Multi-Agent Configuration Tools

Public shared configuration for Claude Code, Codex, and IBM Bob.

This repository combines common development standards, language references,
workflow skills, Claude commands, Codex skills, and Bob rules/modes without
committing host-specific configuration.

## Layout

- `content/` holds agent-neutral instructions, language references, and
  orchestration references.
- `agents/claude/shared/` holds Claude-native `CLAUDE.md`, settings, commands,
  status line, and skills.
- `agents/codex/shared/` holds Codex-native `AGENTS.md`, config, and skills.
- `agents/bob/shared/` holds Bob-native `AGENTS.md`, settings, MCP config,
  custom modes, rules, and skills.
- `examples/hosts/` shows private overlay shapes with placeholder values only.
- `examples/bob-project/` shows Bob project-local `.bob/` conventions.

## Install

Bootstrap local tooling:

```sh
./install-tools.sh
just setup
```

`./install-tools.sh` is the first-run path for clones that do not have `just`
yet. It checks and installs `just`, `jq`, `rg`, `shellcheck`, `shfmt`, `gh`,
`prek`, `actionlint`, and `zizmor`.

If a fallback installer places tools in a directory that was not already on your
shell `PATH`, start a new shell or add the printed tool directory before running
`just`. To install tools and enable hooks in one bootstrap step, run:

```sh
AGENT_CONFIG_SETUP_HOOKS=1 ./install-tools.sh
```

Check local tooling without installing anything:

```sh
./install-tools.sh --check
```

The tool installer supports macOS with Homebrew and Linux via `/etc/os-release`
family detection for Ubuntu/Debian, Fedora, and RHEL-family systems. It uses
package managers first, then pinned fallbacks only when the required runtime is
already installed.

Set up or refresh local git hooks:

```sh
just hooks
```

Install one agent:

```sh
./install.sh --agent claude
./install.sh --agent codex
./install.sh --agent bob
```

Install all supported agents:

```sh
./install.sh --agent all
```

To test install output without touching live config directories:

```sh
tmpdir="$(mktemp -d)"
HOME="$tmpdir/home" \
CLAUDE_CONFIG_DIR="$tmpdir/home/.claude" \
CODEX_CONFIG_DIR="$tmpdir/home/.codex" \
BOB_CONFIG_DIR="$tmpdir/home/.bob" \
AGENT_CONFIG_PRIVATE_DIR="$tmpdir/private" \
AGENT_CONFIG_HOST=example-host \
./install.sh --agent all
```

Claude MCP registration is opt-in because it writes through the Claude CLI to
user-scope MCP state outside the selected config directory:

```sh
AGENT_CONFIG_REGISTER_CLAUDE_MCP=1 ./install.sh --agent claude
```

## Private Overlays

Host overlays stay outside this public repository:

```text
${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/hosts/<host>/<agent>/
```

Supported overlay files:

- Claude: `settings.overlay.json`
- Codex: `config.overlay.toml`
- Bob: `settings.overlay.json`, `mcp.overlay.json`

If an overlay is absent, the installer uses the public base and reports that no
private overlay was applied. Secrets should stay in environment variables or in
private overlay files outside this repo.

## IBM Bob Notes

Bob has separate global paths for some IDE and Shell settings. The installer
copies the public custom mode to both:

- `~/.bob/settings/custom_modes.yaml`
- `~/.bob/custom_modes.yaml`

It also writes MCP config to both:

- `~/.bob/mcp.json`
- `~/.bob/mcp_settings.json`

Bob project-local examples live under `examples/bob-project/.bob/`.

## Verification

Run the full local guardrail suite:

```sh
just verify
```

Run `just format` to apply shell formatting. CI runs `just ci`, which runs
`just verify` and then `prek run --all-files` to prove the hook configuration.

`./install-test.sh` installs every agent into temporary directories, applies
private overlay fixtures, checks generated files, verifies manifest pruning, and
verifies managed-file drift backup.

`./scripts/check-public-safety.sh` scans for denied host-specific paths, local
network addresses, auth headers, and common secret token shapes.

## Decision Records

Architecture decisions live in `docs/adr/`; explicitly deferred work lives in
`docs/debt/`. Number the two directories independently: list the numbered files
in the relevant directory and increment its highest four-digit prefix. Do not
maintain a hand-written index.

An ADR is named `NNNN-slug.md`, starts with `# NNNN — Title`, and has non-empty
`## Status`, `## Context`, `## Decision`, `## Consequences`, and
`## Considered & rejected` sections. Its status is `Proposed`, `Deferred`, or
`Accepted`, `Rejected`, or `Superseded` followed by an ISO date in parentheses.
Record supersession in the old ADR with this status banner, pointing to the new
ADR:

```markdown
> **Superseded by [NNNN](NNNN-slug.md)** (YYYY-MM-DD)
```

A debt record uses the same file and title convention. It has non-empty
`## Status`, `## Concern`, `## Why deferred`, `## Non-regression boundary`,
`## What would resolve it`, and `## Provenance` sections. Open records use an
`Open` status followed by `review-by: YYYY-MM-DD`. Provenance includes at least
one `target: path` line. Resolve a record in place by removing `review-by:` and
replacing `Open` with:

```markdown
> **Resolved by <what>** (YYYY-MM-DD)
```

Merged records are append-only except for their lifecycle markers. Create a new
ADR instead of rewriting an accepted decision; supersede the old one when the
new decision is accepted. Resolve debt in place when its stated condition is
met.

If a numbering collision or mistake requires renumbering a merged record, move it
to an unused four-digit number and update the H1 number in the same change. Do
not alter substantive text. The gate accepts the move only when the destination
did not exist at the base commit and canonicalized content is identical;
marker-only normalization may accompany it. New records still increment the
highest current number in their own directory.

For legacy records, preview marker-only migrations before writing them:

```sh
RECORD_PROFILES="adr debt" ./.github/scripts/migrate-records.sh
RECORD_PROFILES="adr debt" ./.github/scripts/migrate-records.sh --write
```

Review every item the dry run leaves for a human. For a missing lifecycle date,
inspect repository history:

```sh
git log --follow --format=%cs -- <record>
```

Add the date of the commit that established the lifecycle state; do not invent
the current date. Apply the marker rewrites with `--write`, then make the
evidenced Status or required-section completion in the same dedicated migration
commit without rewriting existing prose.

Include every printed `Migrated-markers:` trailer; those trailers enumerate the
automatic marker rewrites, not the required human completions. Run `just verify`
after creating, superseding, resolving, or migrating a record.

The root package under `.github/scripts/` owns the repository gate. Its checker,
suite, migrator, and `adr` and `debt` profiles must remain byte-identical to both
agent projections under `agents/claude/shared/skills/decision-records/assets/`
and `agents/codex/shared/skills/decision-records/assets/`; `just records` checks
that invariant. CI runs the gate, but it remains advisory until branch
protection requires the `Verify` check; issue #16 tracks that repository setting.

## Source Material

This repo was designed from the existing local Claude Code and Codex config
repositories plus public IBM Bob documentation and examples:

- IBM Bob custom modes: https://bob.ibm.com/docs/ide/configuration/custom-modes
- IBM Bob Shell custom modes:
  https://bob.ibm.com/docs/shell/configuration/custom-modes-bobshell
- IBM Bob skills: https://bob.ibm.com/docs/ide/features/skills
- IBM Bob rules: https://bob.ibm.com/docs/ide/configuration/rules
- IBM Bob IDE MCP: https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob
- IBM Bob Shell MCP: https://bob.ibm.com/docs/shell/configuration/mcp/mcp-bobshell
