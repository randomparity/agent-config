#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TMP_FILES=()
SKILLS_STAGING=""

usage() {
	cat >&2 <<'EOF'
Usage: ./install.sh --agent claude|codex|bob|all

Environment:
  AGENT_CONFIG_HOST         Override detected host name.
  AGENT_CONFIG_PRIVATE_DIR  Private overlay root; defaults to ~/.config/agent-config.
  CLAUDE_CONFIG_DIR         Claude destination; defaults to ~/.claude.
  CODEX_CONFIG_DIR          Codex destination; defaults to ~/.codex.
  BOB_CONFIG_DIR            Bob destination; defaults to ~/.bob.
EOF
}

cleanup() {
	local path
	for path in "${TMP_FILES[@]+"${TMP_FILES[@]}"}"; do
		if [[ -n "$path" && (-e "$path" || -L "$path") ]]; then
			unlink "$path" ||
				printf 'install: could not remove temporary file: %s\n' "$path" >&2
		fi
	done
	# Reported rather than propagated: a trap whose last command fails replaces a
	# successful exit status, so an undeletable staging tree would turn a
	# completed install into a reported failure.
	if [[ -n "$SKILLS_STAGING" && -d "$SKILLS_STAGING" ]]; then
		rm -R "$SKILLS_STAGING" ||
			printf 'install: could not remove staging directory: %s\n' "$SKILLS_STAGING" >&2
	fi
}
trap cleanup EXIT

require_command() {
	local command_name="$1"

	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'install: %s is required but was not found in PATH\n' "$command_name" >&2
		exit 1
	fi
}

new_temp_file() {
	local path

	path="$(mktemp "${TMPDIR:-/tmp}/agent-config.XXXXXX")"
	TMP_FILES+=("$path")
	printf '%s\n' "$path"
}

# The canonical skills tree carries test-only assets in `testdata/` entries: the
# contract suites and the fixtures they stage into a tree they assemble at run
# time. They reach no installed agent, because a fixture that answers a tracker
# read with a fabricated issue is indistinguishable from a real read at the call
# site, and a suite is of no use to an agent that will never run it.
#
# Matched by name and not by type: `install-test.sh` compares with `diff -x
# testdata`, which excludes a match of either kind, so a `-type d` filter here
# would let a plain file named `testdata` ship with the canonical comparison
# masking it (ADR 0025).
#
# Filter by staging a copy and installing that, rather than by deleting from the
# destination afterwards. The destination then stays byte-comparable to its
# source, so a reinstall reports unchanged instead of reading the missing
# fixtures as drift and recopying the whole tree every run.
stage_skills() {
	SKILLS_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-skills.XXXXXX")"
	cp -pR "$REPO/content/skills" "$SKILLS_STAGING/skills"
	find "$SKILLS_STAGING/skills" -name testdata -prune -exec rm -R {} +
}

detect_host() {
	if [[ -n "${AGENT_CONFIG_HOST:-}" ]]; then
		printf '%s\n' "$AGENT_CONFIG_HOST"
		return 0
	fi

	case "$(uname -s)" in
	Darwin) printf 'mac\n' ;;
	Linux) hostname -s ;;
	*)
		printf 'install: unsupported host OS: %s\n' "$(uname -s)" >&2
		exit 1
		;;
	esac
}

canonical_dir() {
	local dir="$1"

	mkdir -p "$dir"
	(cd "$dir" && pwd -P)
}

private_overlay_dir() {
	local agent="$1"
	local host="$2"
	local private_root="${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}"

	printf '%s/hosts/%s/%s\n' "$private_root" "$host" "$agent"
}

ensure_safe_rel() {
	local rel="$1"

	case "$rel" in
	"" | /* | *"/../"* | "../"* | */.. | ..)
		printf 'install: refusing unsafe managed path: %s\n' "$rel" >&2
		exit 1
		;;
	esac
}

ancestor_dirs() {
	local dest_dir="$1"
	local rel="$2"
	local prefix="" rest

	ensure_safe_rel "$rel"
	case "$rel" in
	*/*) rest="${rel%/*}" ;;
	*) return 0 ;;
	esac

	while [[ -n "$rest" ]]; do
		prefix="$prefix/${rest%%/*}"
		case "$rest" in
		*/*) rest="${rest#*/}" ;;
		*) rest="" ;;
		esac
		printf '%s%s\n' "$dest_dir" "$prefix"
	done
}

ensure_parent_dirs() {
	local dest_dir="$1"
	local rel="$2"
	local dir

	while IFS= read -r dir; do
		if [[ -L "$dir" ]]; then
			printf 'install: refusing to write through symlinked ancestor: %s\n' "$dir" >&2
			exit 1
		fi
		mkdir -p "$dir"
	done < <(ancestor_dirs "$dest_dir" "$rel")
}

remove_dest() {
	local dest_dir="$1"
	local rel="$2"
	local path="$dest_dir/$rel"
	local dir

	ensure_safe_rel "$rel"
	case "$path" in
	"$dest_dir"/?*) ;;
	*)
		printf 'install: refusing to remove path outside destination: %s\n' "$path" >&2
		exit 1
		;;
	esac

	if [[ ! -e "$path" && ! -L "$path" ]]; then
		return 0
	fi

	while IFS= read -r dir; do
		if [[ -L "$dir" ]]; then
			printf 'install: refusing to remove through symlinked ancestor: %s\n' "$dir" >&2
			exit 1
		fi
	done < <(ancestor_dirs "$dest_dir" "$rel")

	if [[ -L "$path" || ! -d "$path" ]]; then
		unlink "$path"
	else
		rm -R "$path"
	fi
}

payload_differs() {
	local src="$1"
	local dest="$2"
	local diff_status
	local source_executables
	local destination_executables

	if [[ -d "$src" && ! -L "$src" ]]; then
		[[ -d "$dest" && ! -L "$dest" ]] || return 0
		if diff -rq "$src" "$dest" >/dev/null 2>&1; then
			diff_status=0
		else
			diff_status="$?"
		fi
		case "$diff_status" in
		0) ;;
		1) return 0 ;;
		*)
			printf 'install: could not compare payload: %s\n' "$dest" >&2
			exit 1
			;;
		esac
		source_executables="$(
			cd "$src" || exit
			find . -type f \( -perm -100 -o -perm -010 -o -perm -001 \) -print |
				LC_ALL=C sort
		)"
		destination_executables="$(
			cd "$dest" || exit
			find . -type f \( -perm -100 -o -perm -010 -o -perm -001 \) -print |
				LC_ALL=C sort
		)"
		[[ "$source_executables" != "$destination_executables" ]]
		return
	fi

	[[ -f "$dest" && ! -L "$dest" ]] || return 0
	cmp -s "$src" "$dest" || return 0
	if [[ -x "$src" ]]; then
		[[ ! -x "$dest" ]]
	else
		[[ -x "$dest" ]]
	fi
}

backup_path() {
	local dest_dir="$1"
	local rel="$2"
	local kind="$3"
	local path="$dest_dir/$rel"
	local backup_dir="$dest_dir/.agent-config-backups/$TIMESTAMP/$kind"

	if [[ ! -e "$path" && ! -L "$path" ]]; then
		return 0
	fi

	mkdir -p "$backup_dir/$(dirname "$rel")"
	cp -pR "$path" "$backup_dir/$rel"
}

manifest_contains() {
	local manifest_file="$1"
	local rel="$2"

	grep -Fxq -- "$rel" "$manifest_file"
}

write_manifest() {
	local manifest_file="$1"
	shift

	printf '%s\n' "$@" >"$manifest_file"
}

install_managed_path() {
	local dest_dir="$1"
	local src="$2"
	local rel="$3"

	ensure_safe_rel "$rel"
	if [[ ! -e "$src" ]]; then
		printf 'install: missing source for %s: %s\n' "$rel" "$src" >&2
		exit 1
	fi

	ensure_parent_dirs "$dest_dir" "$rel"
	if [[ -L "$dest_dir/$rel" ]]; then
		UPDATED=$((UPDATED + 1))
		backup_path "$dest_dir" "$rel" drift
	elif [[ ! -e "$dest_dir/$rel" ]]; then
		ADDED=$((ADDED + 1))
	elif payload_differs "$src" "$dest_dir/$rel"; then
		UPDATED=$((UPDATED + 1))
		backup_path "$dest_dir" "$rel" drift
	else
		UNCHANGED=$((UNCHANGED + 1))
		MANIFEST_ENTRIES+=("$rel")
		return 0
	fi

	remove_dest "$dest_dir" "$rel"
	cp -pR "$src" "$dest_dir/$rel"
	MANIFEST_ENTRIES+=("$rel")
}

prune_removed() {
	local dest_dir="$1"
	local old_manifest="$2"
	local new_manifest="$3"
	local rel

	if [[ ! -f "$old_manifest" ]]; then
		return 0
	fi

	while IFS= read -r rel || [[ -n "$rel" ]]; do
		[[ -n "$rel" ]] || continue
		ensure_safe_rel "$rel"
		if manifest_contains "$new_manifest" "$rel"; then
			continue
		fi
		if [[ ! -e "$dest_dir/$rel" && ! -L "$dest_dir/$rel" ]]; then
			continue
		fi
		backup_path "$dest_dir" "$rel" pruned
		remove_dest "$dest_dir" "$rel"
		PRUNED=$((PRUNED + 1))
	done <"$old_manifest"
}

finish_agent() {
	local agent="$1"
	local dest_dir="$2"
	local manifest="$dest_dir/.agent-config-manifest"
	local new_manifest

	new_manifest="$(new_temp_file)"
	write_manifest "$new_manifest" "${MANIFEST_ENTRIES[@]}"
	prune_removed "$dest_dir" "$manifest" "$new_manifest"
	cp "$new_manifest" "$manifest"

	printf '%s: config dir %s\n' "$agent" "$dest_dir"
	printf '%s: %s added, %s updated, %s unchanged, %s pruned\n' \
		"$agent" "$ADDED" "$UPDATED" "$UNCHANGED" "$PRUNED"
	printf '%s: manifest %s\n' "$agent" "$manifest"
}

start_agent() {
	MANIFEST_ENTRIES=()
	ADDED=0
	UPDATED=0
	UNCHANGED=0
	PRUNED=0
}

merge_json_settings() {
	local base="$1"
	local overlay="$2"
	local output="$3"

	require_command jq
	if [[ -f "$overlay" ]]; then
		jq -s '.[0] * .[1]' "$base" "$overlay" >"$output"
		printf 'install: applied private overlay %s\n' "$overlay"
	else
		jq '.' "$base" >"$output"
		printf 'install: no private overlay at %s\n' "$overlay"
	fi
}

emit_root_settings() {
	awk '
    /^[[:space:]]*\[/ { in_table = 1 }
    !in_table { print }
  ' "$1"
}

emit_table_settings() {
	awk '
    /^[[:space:]]*\[/ { in_table = 1 }
    in_table { print }
  ' "$1"
}

supports_tomllib() {
	command -v python3 >/dev/null 2>&1 &&
		python3 -c 'import tomllib' >/dev/null 2>&1
}

validate_toml() {
	local path="$1"

	if supports_tomllib; then
		python3 - "$path" <<'PY'
import pathlib
import sys
import tomllib

path = pathlib.Path(sys.argv[1])
try:
    tomllib.loads(path.read_text())
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"{path}: invalid TOML: {exc}") from exc
PY
	else
		printf 'install: skipped TOML validation because python3 tomllib is unavailable\n'
	fi
}

merge_toml_config() {
	local base="$1"
	local overlay="$2"
	local output="$3"

	if [[ -f "$overlay" ]]; then
		{
			emit_root_settings "$base"
			printf '\n'
			emit_root_settings "$overlay"
			printf '\n'
			emit_table_settings "$base"
			printf '\n'
			emit_table_settings "$overlay"
		} >"$output"
		printf 'install: applied private overlay %s\n' "$overlay"
	else
		{
			emit_root_settings "$base"
			printf '\n'
			emit_table_settings "$base"
		} >"$output"
		printf 'install: no private overlay at %s\n' "$overlay"
	fi
	validate_toml "$output"
}

validate_yaml_if_possible() {
	local path="$1"

	if command -v ruby >/dev/null 2>&1; then
		ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$path"
	else
		printf 'install: skipped YAML validation because ruby is unavailable\n'
	fi
}

install_common_content() {
	local dest_dir="$1"

	# Both sources are directories, so install_managed_path's cp -pR ships them
	# whole to all three agents. Their membership is declared in the manifest in
	# scripts/check-deployed-membership.sh, and a file added here without a
	# manifest line fails that gate. Four directory sources reach
	# install_managed_path in all: these two, agents/bob/shared/rules, and the
	# staged skills tree, which is deliberately not declared (ADR 0045). A fifth
	# needs adding to the manifest.
	install_managed_path "$dest_dir" "$REPO/content/languages" "languages"
	install_managed_path "$dest_dir" "$REPO/content/references" "references"
	install_managed_path \
		"$dest_dir" \
		"$REPO/docs/licenses/superpowers.LICENSE" \
		"licenses/superpowers.LICENSE"
}

maybe_configure_claude_mcp() {
	if [[ "${AGENT_CONFIG_REGISTER_CLAUDE_MCP:-0}" != "1" ]]; then
		printf 'claude: MCP registration skipped; set AGENT_CONFIG_REGISTER_CLAUDE_MCP=1 to opt in\n'
		return 0
	fi
	if ! command -v claude >/dev/null 2>&1; then
		printf 'claude: MCP registration skipped because claude CLI is unavailable\n'
		return 0
	fi

	claude mcp remove -s user context7 >/dev/null 2>&1 || true
	claude mcp add -s user context7 -- npx -y @upstash/context7-mcp
	if [[ -n "${EXA_API_KEY:-}" ]]; then
		claude mcp remove -s user exa >/dev/null 2>&1 || true
		claude mcp add -s user exa -e "EXA_API_KEY=$EXA_API_KEY" -- npx -y exa-mcp-server
	else
		printf 'claude: exa MCP skipped because EXA_API_KEY is unset\n'
	fi
}

install_claude() {
	local host="$1"
	local dest_dir
	local overlay_dir
	local settings_tmp

	start_agent
	dest_dir="$(canonical_dir "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"
	overlay_dir="$(private_overlay_dir claude "$host")"
	settings_tmp="$(new_temp_file)"

	merge_json_settings \
		"$REPO/agents/claude/shared/settings.base.json" \
		"$overlay_dir/settings.overlay.json" \
		"$settings_tmp"

	install_managed_path "$dest_dir" "$settings_tmp" "settings.json"
	install_managed_path "$dest_dir" "$REPO/agents/claude/shared/CLAUDE.md" "CLAUDE.md"
	install_managed_path "$dest_dir" "$REPO/agents/claude/shared/statusline.sh" "statusline.sh"
	install_managed_path "$dest_dir" "$SKILLS_STAGING/skills" "skills"
	install_common_content "$dest_dir"
	maybe_configure_claude_mcp
	finish_agent claude "$dest_dir"
}

install_codex() {
	local host="$1"
	local dest_dir
	local overlay_dir
	local config_tmp

	start_agent
	dest_dir="$(canonical_dir "${CODEX_CONFIG_DIR:-$HOME/.codex}")"
	overlay_dir="$(private_overlay_dir codex "$host")"
	config_tmp="$(new_temp_file)"

	merge_toml_config \
		"$REPO/agents/codex/shared/config.base.toml" \
		"$overlay_dir/config.overlay.toml" \
		"$config_tmp"

	install_managed_path "$dest_dir" "$config_tmp" "config.toml"
	install_managed_path "$dest_dir" "$REPO/agents/codex/shared/AGENTS.md" "AGENTS.md"
	install_managed_path "$dest_dir" "$SKILLS_STAGING/skills" "skills"
	install_common_content "$dest_dir"
	finish_agent codex "$dest_dir"
}

install_bob() {
	local host="$1"
	local dest_dir
	local overlay_dir
	local settings_tmp
	local mcp_tmp
	local bob_modes

	start_agent
	dest_dir="$(canonical_dir "${BOB_CONFIG_DIR:-$HOME/.bob}")"
	overlay_dir="$(private_overlay_dir bob "$host")"
	settings_tmp="$(new_temp_file)"
	mcp_tmp="$(new_temp_file)"
	bob_modes="$REPO/agents/bob/shared/custom_modes.yaml"

	merge_json_settings \
		"$REPO/agents/bob/shared/settings.base.json" \
		"$overlay_dir/settings.overlay.json" \
		"$settings_tmp"
	merge_json_settings \
		"$REPO/agents/bob/shared/mcp.json" \
		"$overlay_dir/mcp.overlay.json" \
		"$mcp_tmp"
	validate_yaml_if_possible "$bob_modes"

	install_managed_path "$dest_dir" "$settings_tmp" "settings.json"
	install_managed_path "$dest_dir" "$mcp_tmp" "mcp.json"
	install_managed_path "$dest_dir" "$mcp_tmp" "mcp_settings.json"
	install_managed_path "$dest_dir" "$REPO/agents/bob/shared/AGENTS.md" "AGENTS.md"
	install_managed_path "$dest_dir" "$bob_modes" "settings/custom_modes.yaml"
	install_managed_path "$dest_dir" "$bob_modes" "custom_modes.yaml"
	# A directory source, so cp -pR ships the tree whole into Bob's rules
	# directory. Its membership is declared in the manifest in
	# scripts/check-deployed-membership.sh.
	install_managed_path "$dest_dir" "$REPO/agents/bob/shared/rules" "rules"
	install_managed_path "$dest_dir" "$SKILLS_STAGING/skills" "skills"
	install_common_content "$dest_dir"
	finish_agent bob "$dest_dir"
}

install_agent() {
	local agent="$1"
	local host="$2"

	case "$agent" in
	claude) install_claude "$host" ;;
	codex) install_codex "$host" ;;
	bob) install_bob "$host" ;;
	*)
		printf 'install: unknown agent: %s\n' "$agent" >&2
		exit 1
		;;
	esac
}

main() {
	local target="${2:-}"
	local host

	if [[ $# -ne 2 || "${1:-}" != "--agent" ]]; then
		usage
		exit 1
	fi

	case "$target" in
	claude | codex | bob | all) ;;
	*)
		usage
		exit 1
		;;
	esac

	host="$(detect_host)"
	printf 'install: host %s\n' "$host"
	stage_skills

	if [[ "$target" == "all" ]]; then
		install_agent claude "$host"
		install_agent codex "$host"
		install_agent bob "$host"
	else
		install_agent "$target" "$host"
	fi
}

main "$@"
