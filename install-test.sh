#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'install-test: %s\n' "$*" >&2
	exit 1
}

assert_file() {
	[[ -f "$1" ]] || fail "expected file: $1"
}

assert_same_file() {
	local expected="$1"
	local actual="$2"

	cmp -s "$expected" "$actual" ||
		fail "expected identical files: $expected and $actual"
}

assert_not_file() {
	[[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
	local file="$1"
	local expected="$2"
	grep -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
}

assert_worktree_baseline_transcripts() {
	local skill_file="$1"

	# WT-BL-00: a passing baseline remains ready to implement.
	assert_contains "$skill_file" '**If tests pass:** Report ready.'
	# WT-BL-01: interactive failure preserves the human decision gate.
	assert_contains "$skill_file" '**Interactive mode:**'
	assert_contains "$skill_file" \
		'Report the failures, ask whether to proceed or investigate, and wait.'
	# WT-BL-02: unresolved dispatched failure returns control as a blocker.
	assert_contains "$skill_file" '**Dispatched mode without resolving authority:**'
	assert_contains "$skill_file" \
		'Report the failures as a blocker and return to the caller.'
	# WT-BL-03: only authority that addresses the failed baseline resolves the gate.
	assert_contains "$skill_file" '**Dispatched mode with resolving authority:**'
	assert_contains "$skill_file" \
		'An applicable caller instruction or repository rule must explicitly address the failed baseline.'
	assert_contains "$skill_file" \
		'Report the failures, then follow the explicit applicable instruction or repository rule.'
	# WT-BL-04: generic dispatch does not imply permission to continue.
	assert_contains "$skill_file" \
		'Generic dispatch, autonomy, or task-completion language does not resolve the gate.'
	# WT-BL-05: unresolved ambiguity or conflict follows the blocker branch.
	assert_contains "$skill_file" \
		'If instruction priority does not yield one unambiguous action, return the blocker.'
}

assert_line() {
	local file="$1"
	local expected="$2"

	grep -Fxq -- "$expected" "$file" ||
		fail "expected $file to contain line: $expected"
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

# The canonical tree carries test-only assets under `testdata/` directories that
# the installer filters out, so the installed tree is the canonical one minus
# those. Compare with the same exclusion rather than loosening the comparison.
assert_canonical_skills() {
	local destination="$1"
	local expected_executables
	local actual_executables
	local count

	diff -rq -x testdata "$REPO/content/skills" "$destination/skills" >/dev/null ||
		fail "installed skills differ from canonical tree: $destination/skills"
	expected_executables="$(
		cd "$REPO/content/skills"
		find . -type d -name testdata -prune -o -type f \
			\( -perm -100 -o -perm -010 -o -perm -001 \) -print |
			LC_ALL=C sort
	)"
	actual_executables="$(
		cd "$destination/skills"
		find . -type f \( -perm -100 -o -perm -010 -o -perm -001 \) -print |
			LC_ALL=C sort
	)"
	[[ "$actual_executables" == "$expected_executables" ]] ||
		fail "installed skill modes differ from canonical tree: $destination/skills"
	count="$(find "$destination/skills" ! -path "$destination/skills" \
		-prune -type d -print | wc -l)"
	[[ "$count" -eq 35 ]] ||
		fail "expected 35 canonical skills in $destination/skills, got $count"
	assert_file "$destination/skills/simplify-changes/SKILL.md"
	assert_not_file "$destination/skills/simplify/SKILL.md"
}

# The tracker contract suite's stub profile answers a read with a fabricated
# issue. Installed, it is selectable as though it were a tracker and nothing at
# the call site distinguishes its payload from a real one, so assert both that
# it is absent and that naming it fails the way any unimplemented tracker does.
assert_no_stub_profile() {
	local destination="$1"
	local assets="$destination/skills/github-tracking/assets"
	local leftover
	local status=0
	local available

	assert_file "$assets/tracker.sh"
	assert_file "$assets/profiles/github.sh"
	assert_not_file "$assets/profiles/fixture.sh"
	leftover="$(find "$destination/skills" -type d -name testdata -print)"
	[[ -z "$leftover" ]] ||
		fail "installed tree carries a test-only asset directory: $leftover"

	"$assets/tracker.sh" view --profile fixture 1 \
		>"$tmpdir/tracker-out" 2>"$tmpdir/tracker-err" || status="$?"
	[[ "$status" -eq 1 ]] ||
		fail "installed tracker did not reject --profile fixture (exit $status)"
	assert_json_value "$tmpdir/tracker-err" ".error" "usage"
	available="$(jq -r '.message | sub("^.*available: "; "")' "$tmpdir/tracker-err")"
	[[ "$available" != *fixture* ]] ||
		fail "installed tracker still advertises the stub profile: $available"
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
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-test.XXXXXX")"
trap 'rm -R "$tmpdir"' EXIT

assert_worktree_baseline_transcripts \
	"$REPO/content/skills/using-git-worktrees/SKILL.md"

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
assert_no_stub_profile "$CLAUDE_CONFIG_DIR"
assert_not_file "$CLAUDE_CONFIG_DIR/skills/accessibility-reviewer/SKILL.md"
assert_not_file "$CLAUDE_CONFIG_DIR/skills/project-context/SKILL.md"
assert_worktree_baseline_transcripts \
	"$CLAUDE_CONFIG_DIR/skills/using-git-worktrees/SKILL.md"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$CLAUDE_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_file "$CLAUDE_CONFIG_DIR/languages/bash.md"
assert_executable "$CLAUDE_CONFIG_DIR/statusline.sh"
assert_json_value "$CLAUDE_CONFIG_DIR/settings.json" ".env.AGENT_CONFIG_TEST" "claude"

assert_file "$CODEX_CONFIG_DIR/AGENTS.md"
assert_file "$CODEX_CONFIG_DIR/config.toml"
assert_canonical_skills "$CODEX_CONFIG_DIR"
assert_no_stub_profile "$CODEX_CONFIG_DIR"
assert_not_file "$CODEX_CONFIG_DIR/skills/accessibility-reviewer/SKILL.md"
assert_not_file "$CODEX_CONFIG_DIR/skills/project-context/SKILL.md"
assert_worktree_baseline_transcripts \
	"$CODEX_CONFIG_DIR/skills/using-git-worktrees/SKILL.md"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$CODEX_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_file "$CODEX_CONFIG_DIR/references/orchestration.md"
assert_toml_contains "$CODEX_CONFIG_DIR/config.toml" 'agent_config_test = "codex"'

assert_file "$BOB_CONFIG_DIR/settings.json"
assert_file "$BOB_CONFIG_DIR/settings/custom_modes.yaml"
assert_file "$BOB_CONFIG_DIR/custom_modes.yaml"
assert_file "$BOB_CONFIG_DIR/mcp.json"
assert_file "$BOB_CONFIG_DIR/mcp_settings.json"
assert_file "$BOB_CONFIG_DIR/rules/global-development-standards.md"
assert_canonical_skills "$BOB_CONFIG_DIR"
assert_no_stub_profile "$BOB_CONFIG_DIR"
assert_not_file "$BOB_CONFIG_DIR/skills/accessibility-reviewer/SKILL.md"
assert_not_file "$BOB_CONFIG_DIR/skills/project-context/SKILL.md"
assert_worktree_baseline_transcripts \
	"$BOB_CONFIG_DIR/skills/using-git-worktrees/SKILL.md"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$BOB_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_json_value "$BOB_CONFIG_DIR/settings.json" ".agentConfigTest.bob" "true"
assert_json_value "$BOB_CONFIG_DIR/mcp.json" '.mcpServers["example-docs"].command' "npx"
assert_json_value "$BOB_CONFIG_DIR/mcp_settings.json" '.mcpServers["example-docs"].command' "npx"

assert_line "$CLAUDE_CONFIG_DIR/.agent-config-manifest" \
	"licenses/superpowers.LICENSE"
assert_line "$CODEX_CONFIG_DIR/.agent-config-manifest" \
	"licenses/superpowers.LICENSE"
assert_line "$BOB_CONFIG_DIR/.agent-config-manifest" \
	"licenses/superpowers.LICENSE"

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
write_text "$CLAUDE_CONFIG_DIR/licenses/superpowers.LICENSE" \
	"local license drift before reinstall"
AGENT_CONFIG_HOST=test-host ./install.sh --agent claude

assert_contains "$CLAUDE_CONFIG_DIR/CLAUDE.md" "# Global Development Standards"
assert_tree_contains "$CLAUDE_CONFIG_DIR/.agent-config-backups" "local drift before reinstall"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$CLAUDE_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_tree_contains "$CLAUDE_CONFIG_DIR/.agent-config-backups" \
	"local license drift before reinstall"

printf 'install-test: ok\n'
