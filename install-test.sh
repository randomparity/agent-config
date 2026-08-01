#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'install-test: %s\n' "$*" >&2
	exit 1
}

assert_file() {
	[[ -f "$1" ]] || fail "expected file: $1"
}

assert_not_file() {
	[[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
	local file="$1"
	local expected="$2"
	grep -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
}

assert_json_value() {
	local file="$1"
	local filter="$2"
	local expected="$3"
	local actual

	actual="$(jq -r "$filter" "$file")"
	[[ "$actual" == "$expected" ]] ||
		fail "expected $file $filter to be $expected, got $actual"
}

assert_toml_contains() {
	assert_contains "$1" "$2"
}

assert_executable() {
	[[ -x "$1" ]] || fail "expected executable: $1"
}

assert_canonical_skills() {
	local destination="$1"
	local expected_identity
	local actual_identity
	local count

	expected_identity="$(identity_path "$REPO/content/skills")"
	actual_identity="$(identity_path "$destination/skills")"
	[[ "$actual_identity" == "$expected_identity" ]] ||
		fail "installed skills differ from canonical tree: $destination/skills"
	count="$(find "$destination/skills" ! -path "$destination/skills" \
		-prune -type d -print | wc -l)"
	[[ "$count" -eq 35 ]] ||
		fail "expected 35 canonical skills in $destination/skills, got $count"
	assert_file "$destination/skills/simplify-changes/SKILL.md"
	assert_not_file "$destination/skills/simplify/SKILL.md"
}

assert_tree_contains() {
	local dir="$1"
	local expected="$2"

	rg -q --fixed-strings "$expected" "$dir" ||
		fail "expected $dir to contain: $expected"
}

write_json() {
	local path="$1"
	local body="$2"

	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$body" >"$path"
}

write_text() {
	local path="$1"
	local body="$2"

	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$body" >"$path"
}

seed_stale_manifest() {
	local dest="$1"

	mkdir -p "$dest"
	write_text "$dest/stale-managed.txt" "stale"
	write_text "$dest/runtime-state.txt" "runtime"
	write_text "$dest/.agent-config-manifest" "stale-managed.txt"
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/install-identity.sh
# Resolved from the repository root established above.
# shellcheck disable=SC1091
source "$REPO/scripts/install-identity.sh"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-test.XXXXXX")"
trap 'rm -R "$tmpdir"' EXIT

export HOME="$tmpdir/home"
export CLAUDE_CONFIG_DIR="$tmpdir/home/.claude"
export CODEX_CONFIG_DIR="$tmpdir/home/.codex"
export BOB_CONFIG_DIR="$tmpdir/home/.bob"
export AGENT_CONFIG_PRIVATE_DIR="$tmpdir/private"
export AGENT_CONFIG_REGISTER_CLAUDE_MCP=0

mkdir -p "$HOME"
seed_stale_manifest "$CLAUDE_CONFIG_DIR"
seed_stale_manifest "$CODEX_CONFIG_DIR"
seed_stale_manifest "$BOB_CONFIG_DIR"

write_json \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/claude/settings.overlay.json" \
	'{"env":{"AGENT_CONFIG_TEST":"claude"}}'
write_text \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/codex/config.overlay.toml" \
	'agent_config_test = "codex"'
write_json \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/bob/settings.overlay.json" \
	'{"agentConfigTest":{"bob":true}}'
write_json \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/bob/mcp.overlay.json" \
	'{
  "mcpServers": {
    "example-docs": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-fetch"]
    }
  }
}'

AGENT_CONFIG_HOST=test-host ./install.sh --agent all

assert_file "$CLAUDE_CONFIG_DIR/CLAUDE.md"
assert_file "$CLAUDE_CONFIG_DIR/settings.json"
assert_canonical_skills "$CLAUDE_CONFIG_DIR"
assert_file "$CLAUDE_CONFIG_DIR/languages/bash.md"
assert_executable "$CLAUDE_CONFIG_DIR/statusline.sh"
assert_json_value "$CLAUDE_CONFIG_DIR/settings.json" ".env.AGENT_CONFIG_TEST" "claude"

assert_file "$CODEX_CONFIG_DIR/AGENTS.md"
assert_file "$CODEX_CONFIG_DIR/config.toml"
assert_canonical_skills "$CODEX_CONFIG_DIR"
assert_file "$CODEX_CONFIG_DIR/references/orchestration.md"
assert_toml_contains "$CODEX_CONFIG_DIR/config.toml" 'agent_config_test = "codex"'

assert_file "$BOB_CONFIG_DIR/settings.json"
assert_file "$BOB_CONFIG_DIR/settings/custom_modes.yaml"
assert_file "$BOB_CONFIG_DIR/custom_modes.yaml"
assert_file "$BOB_CONFIG_DIR/mcp.json"
assert_file "$BOB_CONFIG_DIR/mcp_settings.json"
assert_file "$BOB_CONFIG_DIR/rules/global-development-standards.md"
assert_canonical_skills "$BOB_CONFIG_DIR"
assert_json_value "$BOB_CONFIG_DIR/settings.json" ".agentConfigTest.bob" "true"
assert_json_value "$BOB_CONFIG_DIR/mcp.json" '.mcpServers["example-docs"].command' "npx"
assert_json_value "$BOB_CONFIG_DIR/mcp_settings.json" '.mcpServers["example-docs"].command' "npx"

assert_not_file "$CLAUDE_CONFIG_DIR/stale-managed.txt"
assert_not_file "$CODEX_CONFIG_DIR/stale-managed.txt"
assert_not_file "$BOB_CONFIG_DIR/stale-managed.txt"
assert_file "$CLAUDE_CONFIG_DIR/runtime-state.txt"
assert_file "$CODEX_CONFIG_DIR/runtime-state.txt"
assert_file "$BOB_CONFIG_DIR/runtime-state.txt"

mode_drift="$CODEX_CONFIG_DIR/skills/brainstorming/scripts/start-server.sh"
chmod 644 "$mode_drift"
[[ ! -x "$mode_drift" ]] || fail "expected executable drift fixture: $mode_drift"
AGENT_CONFIG_HOST=test-host ./install.sh --agent codex
assert_executable "$mode_drift"
assert_canonical_skills "$CODEX_CONFIG_DIR"

write_text "$CLAUDE_CONFIG_DIR/CLAUDE.md" "local drift before reinstall"
AGENT_CONFIG_HOST=test-host ./install.sh --agent claude

assert_contains "$CLAUDE_CONFIG_DIR/CLAUDE.md" "# Global Development Standards"
assert_tree_contains "$CLAUDE_CONFIG_DIR/.agent-config-backups" "local drift before reinstall"

printf 'install-test: ok\n'
