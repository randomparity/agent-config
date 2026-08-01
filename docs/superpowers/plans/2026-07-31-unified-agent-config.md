# Unified Agent Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a public, agent-agnostic configuration repository that installs shared and native configuration for Claude Code, Codex, and IBM Bob without committing host-specific state.

**Architecture:** The repo uses ADR 0001's canonical-plus-native layout: neutral prose and references live under `content/`, while deployable agent-specific files live under `agents/<agent>/shared/`. `install.sh` copies curated payloads, generates settings from public bases plus private overlays outside the repo, backs up drift, and prunes only paths it previously owned.

**Tech Stack:** POSIX-style Bash constrained by macOS Bash 3.2, `jq` for JSON merge/validation, Python `tomllib` when available for TOML validation, optional Ruby YAML parsing for Bob custom-mode validation, `shellcheck`, `shfmt`, GitHub CLI.

## Global Constraints

- Public repo must not contain machine names, local paths, trusted-project lists, local IP addresses, auth headers, API keys, runtime state, caches, or tool-generated session data.
- Canonical content owns only neutral subtrees such as language and orchestration references.
- Agent-native payloads own root instruction files, settings, command metadata, skill adapters, modes, MCP files, and paths whose meaning differs by agent.
- Private overlays are read only from `${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/hosts/<host>/<agent>/`.
- Supported installer entry points are `./install.sh --agent claude`, `./install.sh --agent codex`, `./install.sh --agent bob`, and `./install.sh --agent all`.
- Default destinations are `~/.claude`, `~/.codex`, and `~/.bob`, with test overrides through `CLAUDE_CONFIG_DIR`, `CODEX_CONFIG_DIR`, and `BOB_CONFIG_DIR`.
- Bob custom-mode YAML is copied but not merged with a private overlay.
- Bob MCP config is generated to both `mcp.json` and `mcp_settings.json`.
- Do not use symlinks for deployed payloads.
- Verification commands are `shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh`, `shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh`, `./install-test.sh`, and `./scripts/check-public-safety.sh`.

---

## File Structure

- `AGENTS.md`: repo-local public instructions for future agents working in this repository.
- `README.md`: public user documentation for layout, install, private overlays, Bob conventions, and guardrails.
- `.gitignore`: ignores local private overlays and operating-system noise.
- `content/instructions/global-development-standards.md`: agent-neutral standards migrated from existing configuration.
- `content/languages/*.md`: neutral language references copied from the Codex source repo.
- `content/references/orchestration.md`: neutral orchestration reference copied from the Codex source repo.
- `agents/claude/shared/`: Claude-native payload copied from the Claude source repo, excluding host overlays and sanitizing private-path content.
- `agents/codex/shared/`: Codex-native payload copied from the Codex source repo, excluding host overlays and personal model/trust settings that belong in private overlays.
- `agents/bob/shared/`: Bob-native payload using public IBM Bob global paths and public-safe rules, skills, modes, settings, and MCP files.
- `examples/hosts/`: placeholder-only private overlay examples.
- `examples/bob-project/`: placeholder-only Bob project-local examples.
- `scripts/check-public-safety.sh`: scanner for public-leakage patterns.
- `install.sh`: unified installer and manifest/prune logic.
- `install-tools.sh`: tool bootstrap/check script.
- `install-test.sh`: integration tests that install all agents into temp directories.

## Task 1: Public-Safety and Installer Tests

**Files:**
- Create: `scripts/check-public-safety.sh`
- Create: `install-test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: executable `scripts/check-public-safety.sh` with optional positional paths; exits non-zero and prints `public-safety: denied pattern` for denied content.
- Produces: executable `install-test.sh`; calls `./install.sh --agent all` with temp destinations and private overlay fixtures.
- Consumes: no implementation from later tasks; its first run should fail because `install.sh` and payload files do not exist yet.

- [ ] **Step 1: Create the scanner with denied public patterns**

Use `apply_patch` to create `scripts/check-public-safety.sh` with these behaviors:

```sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if (($# > 0)); then
  scan_paths=("$@")
else
  scan_paths=("$ROOT")
fi

denied_patterns=(
  '/Users/[[:alnum:]_][[:alnum:]_.-]+'
  '/home/[[:alnum:]_][[:alnum:]_.-]+'
  '/Volumes/[[:alnum:]_][^`)]*'
  'pdx\.drc'
  'ts\.drc'
  '192\.168\.'
  '(^|[^[:alnum:]])10\.[0-9]{1,3}\.'
  '172\.(1[6-9]|2[0-9]|3[0-1])\.'
  'Basic[[:space:]]+[A-Za-z0-9+/=]{12,}'
  'gh[pousr]_[A-Za-z0-9_]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{20,}'
)

status=0
for pattern in "${denied_patterns[@]}"; do
  if rg -n --hidden --glob '!.git/**' --pcre2 "$pattern" "${scan_paths[@]}"; then
    printf 'public-safety: denied pattern matched: %s\n' "$pattern" >&2
    status=1
  fi
done

exit "$status"
```

- [ ] **Step 2: Create the install integration test harness**

Use `apply_patch` to create `install-test.sh`. Include test helpers named `assert_file`, `assert_not_file`, `assert_contains`, `assert_json_value`, `assert_toml_contains`, and `assert_executable`.

The test must:

```sh
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-test.XXXXXX")"
trap 'rm -R "$tmpdir"' EXIT

export HOME="$tmpdir/home"
export CLAUDE_CONFIG_DIR="$tmpdir/home/.claude"
export CODEX_CONFIG_DIR="$tmpdir/home/.codex"
export BOB_CONFIG_DIR="$tmpdir/home/.bob"
export AGENT_CONFIG_PRIVATE_DIR="$tmpdir/private"
```

It must create private overlays at:

```text
$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/claude/settings.overlay.json
$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/codex/config.overlay.toml
$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/bob/settings.overlay.json
$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/bob/mcp.overlay.json
```

Use these exact overlay values:

```json
{"env":{"AGENT_CONFIG_TEST":"claude"}}
```

```toml
agent_config_test = "codex"
```

```json
{"agentConfigTest":{"bob":true}}
```

```json
{"mcpServers":{"example-docs":{"command":"npx","args":["-y","@modelcontextprotocol/server-fetch"]}}}
```

It must run:

```sh
AGENT_CONFIG_HOST=test-host ./install.sh --agent all
```

It must assert:

```text
$CLAUDE_CONFIG_DIR/CLAUDE.md
$CLAUDE_CONFIG_DIR/settings.json
$CLAUDE_CONFIG_DIR/skills/test-driven-development/SKILL.md
$CLAUDE_CONFIG_DIR/languages/bash.md
$CODEX_CONFIG_DIR/AGENTS.md
$CODEX_CONFIG_DIR/config.toml
$CODEX_CONFIG_DIR/skills/work-issue/SKILL.md
$CODEX_CONFIG_DIR/references/orchestration.md
$BOB_CONFIG_DIR/settings.json
$BOB_CONFIG_DIR/settings/custom_modes.yaml
$BOB_CONFIG_DIR/custom_modes.yaml
$BOB_CONFIG_DIR/mcp.json
$BOB_CONFIG_DIR/mcp_settings.json
$BOB_CONFIG_DIR/rules/global-development-standards.md
$BOB_CONFIG_DIR/skills/test-driven-development/SKILL.md
```

It must pre-create an installer-owned stale path in each destination manifest, run install, and assert those stale paths were pruned while unmanaged runtime files remained.
It must also assert the private overlay values appear in the generated settings or config files.

- [ ] **Step 3: Ignore local-only directories**

Use `apply_patch` to create `.gitignore` with:

```gitignore
.DS_Store
.agent-config-private/
local/
hosts/
```

- [ ] **Step 4: Run the red test**

Run:

```sh
chmod +x scripts/check-public-safety.sh install-test.sh
./install-test.sh
```

Expected: fail because `./install.sh` is not present yet.

- [ ] **Step 5: Commit**

Run:

```sh
git add .gitignore scripts/check-public-safety.sh install-test.sh
git commit -m "test: add unified installer guardrails"
```

## Task 2: Public Content and Native Payloads

**Files:**
- Create: `AGENTS.md`
- Create: `content/instructions/global-development-standards.md`
- Create: `content/languages/bash.md`
- Create: `content/languages/github-actions.md`
- Create: `content/languages/python.md`
- Create: `content/languages/rust.md`
- Create: `content/languages/typescript.md`
- Create: `content/references/orchestration.md`
- Create: `agents/claude/shared/**`
- Create: `agents/codex/shared/**`
- Create: `agents/bob/shared/**`
- Create: `examples/hosts/**`
- Create: `examples/bob-project/**`

**Interfaces:**
- Consumes: `scripts/check-public-safety.sh` from Task 1.
- Produces: all payload paths consumed by `install.sh`.
- Produces: public example overlays consumed by README users, not by tests.

- [ ] **Step 1: Copy canonical content**

Copy neutral language and reference files from `~/src/codex-config/shared`:

```sh
mkdir -p content/instructions content/languages content/references
cp ~/src/codex-config/shared/languages/*.md content/languages/
cp ~/src/codex-config/shared/references/orchestration.md content/references/orchestration.md
cp ~/src/codex-config/shared/AGENTS.md content/instructions/global-development-standards.md
```

Then use `apply_patch` to make `content/instructions/global-development-standards.md`
agent-neutral:

```text
Project-specific instruction files override these defaults.
Before designing, use the installed brainstorming skill when available.
On-demand references are installed under each agent's native reference directory.
```

- [ ] **Step 2: Add repo-local instructions**

Use `apply_patch` to create `AGENTS.md` as a concise repo-local instruction file that says this public repo has no committed host inventory, private overlays live outside the repo, and verification is:

```sh
shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh
shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh
./install-test.sh
./scripts/check-public-safety.sh
```

- [ ] **Step 3: Copy Claude native payload**

Copy Claude-native files from `~/src/claude-config/shared`, omitting source host overlays and omitting the private-memory agent until it is sanitized:

```sh
mkdir -p agents/claude/shared
cp ~/src/claude-config/shared/CLAUDE.md agents/claude/shared/CLAUDE.md
cp ~/src/claude-config/shared/settings.base.json agents/claude/shared/settings.base.json
cp ~/src/claude-config/shared/statusline.sh agents/claude/shared/statusline.sh
cp -R ~/src/claude-config/shared/commands agents/claude/shared/commands
cp -R ~/src/claude-config/shared/skills agents/claude/shared/skills
mkdir -p agents/claude/shared/agents
```

Do not copy `~/src/claude-config/shared/agents/bug-claim-verifier.md` unless every private memory path is removed.

- [ ] **Step 4: Copy Codex native payload**

Copy Codex-native files from `~/src/codex-config/shared`:

```sh
mkdir -p agents/codex/shared
cp ~/src/codex-config/shared/AGENTS.md agents/codex/shared/AGENTS.md
cp ~/src/codex-config/shared/config.base.toml agents/codex/shared/config.base.toml
cp -R ~/src/codex-config/shared/skills agents/codex/shared/skills
```

Then use `apply_patch` to remove personal model preference values from `agents/codex/shared/config.base.toml`, leaving only public-safe feature keys.
The final file should be:

```toml
[features]
goals = true
```

- [ ] **Step 5: Create Bob native payload**

Use `apply_patch` to create:

```text
agents/bob/shared/AGENTS.md
agents/bob/shared/settings.base.json
agents/bob/shared/mcp.json
agents/bob/shared/custom_modes.yaml
agents/bob/shared/rules/global-development-standards.md
agents/bob/shared/skills/test-driven-development/SKILL.md
agents/bob/shared/skills/verification-before-completion/SKILL.md
```

The Bob mode must use supported groups only:

```yaml
customModes:
  - slug: agent-config-maintainer
    name: Agent Config Maintainer
    description: Maintain shared agent configuration with tests and public-safety checks.
    roleDefinition: |
      You maintain public agent configuration for Claude Code, Codex, and IBM Bob.
    whenToUse: Use when editing this configuration repository or testing generated agent config.
    customInstructions: |
      Keep host-specific values out of committed files. Run install tests and the public-safety check before reporting completion.
    groups:
      - read
      - edit
      - execute
      - mcp
      - skill
      - todo
      - subtask
      - subagent
```

- [ ] **Step 6: Create public examples**

Use `apply_patch` to create placeholder examples for:

```text
examples/hosts/example-host/claude/settings.overlay.json
examples/hosts/example-host/codex/config.overlay.toml
examples/hosts/example-host/bob/settings.overlay.json
examples/hosts/example-host/bob/mcp.overlay.json
examples/bob-project/AGENTS.md
examples/bob-project/.bob/custom_modes.yaml
examples/bob-project/.bob/mcp.json
examples/bob-project/.bob/rules/project-standards.md
examples/project-review-skills/project-context/SKILL.md
```

Use only `/path/to/project`, `${EXA_API_KEY}`, and placeholder MCP server names.

- [ ] **Step 7: Run content gates**

Run:

```sh
./scripts/check-public-safety.sh
git diff --check
```

Expected: both pass.

- [ ] **Step 8: Commit**

Run:

```sh
git add AGENTS.md content agents examples .gitignore
git commit -m "feat: add public agent payloads"
```

## Task 3: Unified Installer

**Files:**
- Create: `install.sh`
- Modify: `docs/superpowers/specs/2026-07-31-unified-agent-config-design.md` if implementation documents Bob custom modes to both global paths.

**Interfaces:**
- Consumes: payload directories from Task 2.
- Produces: executable installer accepting `--agent`.
- Produces: manifests `.agent-config-manifest` inside each destination.

- [ ] **Step 1: Implement argument parsing and host resolution**

Use `apply_patch` to create `install.sh` with functions:

```sh
usage()
detect_host()
require_command()
repo_root()
private_overlay_dir(agent)
install_agent(agent)
```

`detect_host` must return `$AGENT_CONFIG_HOST` when set; otherwise `mac` on Darwin and `hostname -s` on other systems.

- [ ] **Step 2: Implement safe file replacement primitives**

Add functions:

```sh
backup_path(path)
replace_file(src, dest)
replace_dir(src, dest)
write_manifest(dest_dir, entries)
prune_removed(dest_dir, new_manifest_file)
```

`replace_file` and `replace_dir` must copy real files or directories, back up existing drift to `.agent-config-backups/<timestamp>/`, and never follow a managed-path symlink as a removal target.

- [ ] **Step 3: Implement Claude settings and payload install**

Add:

```sh
merge_json_settings(base, overlay, output)
install_claude()
```

`install_claude` must copy:

```text
CLAUDE.md
settings.json
statusline.sh
commands/
skills/
languages/
references/
```

It must generate `settings.json` from `agents/claude/shared/settings.base.json` plus optional private `settings.overlay.json`.

- [ ] **Step 4: Implement Codex config and payload install**

Add:

```sh
merge_toml_config(base, overlay, output)
validate_toml(path)
install_codex()
```

`merge_toml_config` must concatenate root keys before table sections for both base and overlay. `install_codex` must copy:

```text
AGENTS.md
config.toml
skills/
languages/
references/
```

- [ ] **Step 5: Implement Bob config and payload install**

Add:

```sh
validate_yaml_if_possible(path)
install_bob()
```

`install_bob` must copy:

```text
AGENTS.md
settings.json
settings/custom_modes.yaml
custom_modes.yaml
mcp.json
mcp_settings.json
rules/
skills/
languages/
references/
```

It must generate both MCP files from `agents/bob/shared/mcp.json` plus optional private `mcp.overlay.json`.

- [ ] **Step 6: Run the previously red integration test**

Run:

```sh
./install-test.sh
```

Expected: pass with a final `install-test: ok` line.

- [ ] **Step 7: Run shell gates**

Run:

```sh
shellcheck install.sh install-test.sh scripts/check-public-safety.sh
shfmt -d install.sh install-test.sh scripts/check-public-safety.sh
```

Expected: both pass with no output.

- [ ] **Step 8: Commit**

Run:

```sh
git add install.sh install-test.sh scripts/check-public-safety.sh docs/superpowers/specs/2026-07-31-unified-agent-config-design.md
git commit -m "feat: add unified installer"
```

## Task 4: Tool Bootstrap and Public Documentation

**Files:**
- Create: `install-tools.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: guardrail command list from the spec.
- Produces: documented local bootstrap through `./install-tools.sh --check`.

- [ ] **Step 1: Add tool bootstrap script**

Use `apply_patch` to create `install-tools.sh` with:

```sh
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---install}"
```

It must check for `jq`, `rg`, `shellcheck`, `shfmt`, and `gh`; install missing tools with Homebrew on macOS when `brew` exists; and fall back to pinned Go installs only for `shfmt@v3.13.1` and `actionlint@v1.7.12` if those commands are added to the script. `--check` must report missing commands and exit non-zero without installing.

- [ ] **Step 2: Replace README with public setup docs**

Use `apply_patch` to replace `README.md` with sections:

```text
Multi-Agent Configuration Tools
Layout
Install
Private Overlays
IBM Bob Notes
Verification
Source Material
```

The README must show exact commands for `./install.sh --agent all`, temp-destination test installs, and the four verification commands.

- [ ] **Step 3: Run docs and shell gates**

Run:

```sh
shellcheck install.sh install-tools.sh install-test.sh scripts/check-public-safety.sh
shfmt -d install.sh install-tools.sh install-test.sh scripts/check-public-safety.sh
./scripts/check-public-safety.sh
git diff --check
```

Expected: all pass.

- [ ] **Step 4: Commit**

Run:

```sh
git add install-tools.sh README.md
git commit -m "docs: document unified config setup"
```

## Task 5: Final Verification and PR Preparation

**Files:**
- Modify: issue #1 comments through `gh`
- Modify: GitHub PR metadata through `gh`

**Interfaces:**
- Consumes: all repo files.
- Produces: branch pushed to `origin/feat/unified-agent-config-1`.
- Produces: PR linked to issue #1.

- [ ] **Step 1: Run the full local guardrail suite**

Run:

```sh
shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh
shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh
./install-test.sh
./scripts/check-public-safety.sh
```

Expected: all pass.

- [ ] **Step 2: Inspect the full diff**

Run:

```sh
git diff --stat main...
git diff --check main...
git status --short
```

Expected: diff check passes and status is clean before pushing.

- [ ] **Step 3: Push the branch**

Run:

```sh
git push -u origin feat/unified-agent-config-1
```

- [ ] **Step 4: Create a pull request**

Run:

```sh
gh pr create --base main --head feat/unified-agent-config-1 --title "Unify agent configuration setup" --body-file /tmp/agent-config-pr-body.md
```

The PR body must include:

```text
Closes #1

## Summary
- Adds canonical shared content and native payloads for Claude Code, Codex, and IBM Bob.
- Adds a unified installer with private overlays, manifest pruning, and drift backup.
- Adds public-safety and install verification.

## Verification
- shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh
- shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh
- ./install-test.sh
- ./scripts/check-public-safety.sh
```

- [ ] **Step 5: Poll PR readiness once local work is pushed**

Run:

```sh
gh pr view --json number,mergeable,mergeStateStatus,headRefName,url
gh pr checks --json name,state,conclusion,link
```

Expected: capture the current readiness state. If CI is absent, report that no remote checks exist and hand off the PR.

## Self-Review

- Spec coverage: Tasks cover canonical content, agent-native payloads, overlays, installer flow, Bob MCP dual paths, Bob custom-mode copy-only behavior, public examples, safety scan, shell gates, install tests, and PR creation.
- Placeholder scan: This plan contains no banned placeholder markers or unnamed error-handling steps.
- Interface consistency: `install-test.sh` expects the files produced by `install.sh`; `install.sh` consumes exactly the payload paths created by Task 2; guardrail commands match the spec except Task 3 omits `install-tools.sh` until Task 4 creates it.
