# Multi-Agent Configuration Tools

Public shared configuration for Claude Code, Codex, and IBM Bob.

This repository combines common development standards, language references,
one shared workflow-skill inventory, and agent-native settings without
committing host-specific configuration.

## Layout

- `content/` holds agent-neutral instructions, language references,
  orchestration references, and the canonical `skills/` tree installed for all
  supported agents.
- `agents/claude/shared/` holds Claude-native `CLAUDE.md`, settings, and status
  line configuration.
- `agents/codex/shared/` holds Codex-native `AGENTS.md` and config.
- `agents/bob/shared/` holds Bob-native `AGENTS.md`, settings, MCP config,
  custom modes, and rules.
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
private overlay fixtures, verifies every installed skill tree against
`content/skills/` including executable modes, checks generated files, verifies
manifest pruning, and verifies managed-file drift backup.

`./scripts/check-skill-layout.sh` rejects agent-native workflow copies and
validates the portable structure of the canonical skill packages.

`./scripts/check-public-safety.sh` scans for denied host-specific paths, local
network addresses, auth headers, and common secret token shapes.

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
