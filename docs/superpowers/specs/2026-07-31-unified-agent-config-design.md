# Unified Agent Config Design

Issue: #1

## Context

This repository is public and will replace two personal, agent-specific
configuration repositories with one agent-agnostic setup for Claude Code, Codex,
and IBM Bob. The existing Claude and Codex repositories already share the same
deployment idea: stable configuration lives in git, host overlays are merged at
install time, live config directories are build outputs, drift is backed up, and
installer-owned paths are pruned through a manifest.

The public repo must not contain host-specific values: machine names, local
paths, trusted-project lists, local IP addresses, auth headers, API keys,
runtime state, caches, or tool-generated session data.

## Goals

- Provide one public repository that documents and deploys agent configuration
  for Claude Code, Codex, and IBM Bob.
- Keep shared standards, language references, and orchestration references in a
  canonical content area.
- Keep agent-native payloads where the agents require incompatible file names,
  metadata, settings formats, command formats, or invocation syntax.
- Preserve the existing safety properties: copy deployment, drift backup,
  manifest-based pruning, generated settings validation, and untouched runtime
  state.
- Support private overlays outside the repository so each host can add local
  paths, trust settings, secrets, and host-only permissions without entering git.
- Ship verification that catches shell problems and accidental public leakage of
  host-specific values.

## Non-Goals

- No live migration of a user's existing `~/.claude`, `~/.codex`, or `~/.bob`
  runtime state.
- No public host inventory.
- No generated plugin installation or marketplace management.
- No attempt to make Claude slash commands, Codex skills, and Bob modes a single
  byte-identical artifact when their native formats differ.
- No committed MCP credentials. Public MCP examples may include unauthenticated
  public documentation servers only.

## Architecture

Use a canonical-plus-native layout:

```text
content/
  instructions/
  languages/
  references/
agents/
  claude/
    shared/
  codex/
    shared/
  bob/
    shared/
examples/
  hosts/
scripts/
  check-public-safety.sh
install.sh
install-tools.sh
install-test.sh
```

`content/` contains material that is deliberately agent-neutral: global
development standards, language references, and orchestration references.
Installers deploy it into each agent's native config tree only for neutral
subtrees whose destination is not agent-specific. Agent-native payloads own root
instruction files, settings, command metadata, skills, modes, MCP files, and any
path whose meaning differs by agent.

`agents/<agent>/shared/` contains deployable native payloads:

- Claude: `CLAUDE.md`, `settings.base.json`, `statusline.sh`, slash commands,
  Claude agents, and Claude-compatible skills.
- Codex: `AGENTS.md`, `config.base.toml`, and Codex skills.
- Bob: `AGENTS.md`, `settings.base.json`, `custom_modes.yaml`, `mcp.json`,
  `rules/`, and `skills/`.

The native payloads are allowed to differ where the tools differ. For example,
Claude command front matter has `allowed-tools`, Codex workflows are skills with
optional `agents/openai.yaml`, and Bob modes grant tool groups such as `read`,
`edit`, `execute`, `mcp`, `skill`, `todo`, `subtask`, and `subagent`.

The repo records the governing architecture in ADR 0001.

## Installer Flow

`install.sh` supports:

```sh
./install.sh --agent claude
./install.sh --agent codex
./install.sh --agent bob
./install.sh --agent all
```

It detects the host as `mac` on Darwin and the short hostname on Linux, but it
does not require a matching committed `hosts/<host>` directory. Instead it looks
for optional private overlays under:

```text
${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/hosts/<host>/<agent>/
```

Per-agent private overlay files:

- Claude: `settings.overlay.json`
- Codex: `config.overlay.toml`
- Bob: `settings.overlay.json`, `mcp.overlay.json`

If an overlay is absent, the installer uses the public base only and reports
that no private overlay was applied. Secrets stay in environment variables or in
private files outside this repo.

Bob custom-mode YAML is not merged in the initial installer. YAML list merging
would either add a new dependency or invite brittle text manipulation, and
custom modes are especially sensitive because they grant tool groups. Host-only
Bob modes therefore stay in Bob's own private global or project configuration
outside this repo until a later issue adds a validated merge strategy.
The public Bob custom-mode file is copied to both global paths documented by
Bob: `~/.bob/settings/custom_modes.yaml` for the IDE and
`~/.bob/custom_modes.yaml` for the Shell.

For each agent, the installer:

1. Resolves the destination directory from an override env var or the native
   default (`~/.claude`, `~/.codex`, `~/.bob`).
2. Generates settings from public base plus private overlay.
3. Validates JSON/TOML/YAML where local tooling is available.
4. Backs up any existing generated settings file.
5. Copies curated payloads into the destination as real files or directories.
6. Backs up drift before replacing installer-owned payloads.
7. Prunes only paths present in that agent's previous manifest but absent from
   the current manifest.
8. Leaves unmanaged runtime files alone.

Claude MCP registration remains a Claude-only optional adapter because Claude
Code uses the `claude mcp` CLI for user-scope MCP registration. Bob MCP stays
file-based. The installer writes Bob global MCP config to the IDE path
`~/.bob/mcp.json` and the Shell path `~/.bob/mcp_settings.json`, because public
Bob docs describe both locations for different surfaces. Codex MCP configuration
is left out until the Codex config surface for this installation is
intentionally added.

## Public Examples

`examples/hosts/` shows private overlay shapes with placeholder values only.
`examples/bob-project/` shows Bob project-local conventions (`AGENTS.md`,
`.bob/custom_modes.yaml`, `.bob/mcp.json`, `.bob/rules/`, and `.bob/skills/`)
without implying those paths are the global install destination. Example files
may use paths like `/path/to/project` and environment placeholders such as
`${EXA_API_KEY}`, but must not include real user names, host names, local IPs,
tokens, Basic Auth headers, trusted-project inventories, or workstation app
paths.

## AI Surface

This repository changes AI behavior through global instructions, skills, slash
commands, Bob custom modes, and MCP affordances.

AI-SPEC: The users are developers running Claude Code, Codex, or IBM Bob; the
trigger is installing or updating this repo's configuration; the input is the
repo's public payload plus optional private overlays; the output is native agent
configuration that guides planning, coding, review, tool use, and verification;
allowed sources are committed public config, local private overlays, and
explicit environment variables; disallowed behavior is leaking private overlay
values, enabling host-specific permissions globally, or documenting unavailable
tools as if installed; fallback behavior is to skip optional integrations with a
clear warning; the cost budget is low fixed context by keeping always-loaded
instructions concise; success is install tests plus leakage checks passing and
native payloads appearing in test destinations.

### Eval Cases

| ID | Failure Mode | Setup | Observable Pass Traits | Gate |
|---|---|---|---|---|
| AI-1 | Global instructions reference the wrong agent config path | Install each agent to a temp directory | Deployed instructions avoid hard-coded `~/.codex` in Claude/Bob and avoid hard-coded `~/.claude` in Codex/Bob | block |
| AI-2 | Bob mode grants missing or unsafe tool groups | Inspect Bob `custom_modes.yaml` | Groups are supported Bob groups and no mode grants command execution without explicit purpose | block |
| AI-3 | Optional MCP server documented as always available | Run install without secret env vars | Installer warns and skips optional integrations; README says how to enable them | warn |
| AI-4 | Skill descriptions bloat always-loaded context | Inspect `SKILL.md` front matter | Descriptions are concise and route to detailed references or scripts | warn |
| AI-5 | Public content leaks a local host value | Run public-safety check | No user home paths, private hostnames, local IPs, tokens, or Basic Auth headers are present | block |

## Threat Model

### Boundary Inventory

- Public git boundary: content moves from local source repos into a public repo.
- Private overlay boundary: private host files are read during install but must
  never be committed or copied into examples.
- Live config boundary: installer writes into `~/.claude`, `~/.codex`, or
  `~/.bob`.
- Manifest boundary: installer prunes files it previously owned.
- Command execution boundary: host-tool bootstrap may install local binaries.
- MCP boundary: Claude and Bob can expose external tools to agents.

### Actors

- Repository maintainer publishing config.
- Local operator installing config on a trusted host.
- Future contributor opening a PR against the public repo.
- Agent session following installed instructions.
- Malicious or mistaken local project that tries to influence config through
  runtime files or symlinked paths.

### Controls

- Public git boundary: `scripts/check-public-safety.sh` scans committed files
  for denied host-specific patterns.
- Private overlay boundary: overlays live under
  `$AGENT_CONFIG_PRIVATE_DIR/hosts/<host>/<agent>/`, outside the repo, and are
  optional.
- Live config boundary: installer canonicalizes destinations, backs up drift,
  and refuses path escapes and symlinked ancestors before removal.
- Manifest boundary: only previous manifest entries can be pruned; unmanaged
  runtime files are never deletion candidates.
- Command execution boundary: `install-tools.sh --check` is non-privileged;
  installation paths that need sudo remain human-run.
- MCP boundary: public MCP files contain no credentials; secret-bearing MCP
  entries belong in private overlays or environment variables.

### Out Of Scope

- A malicious operator can still put secrets in public files before committing;
  the safety scan reduces this risk but is not a substitute for review.
- Agent vendors may change config formats after this design; updates require a
  follow-up issue.
- Windows installation paths are not covered in the initial implementation.

## Verification

- `shellcheck install.sh install-tools.sh scripts/*.sh`
- `shfmt -d install.sh install-tools.sh scripts/*.sh`
- `./install-test.sh`
- `./scripts/check-public-safety.sh`

Because the repo starts with no CI, these commands become the local guardrail
suite and README-documented verification surface.
