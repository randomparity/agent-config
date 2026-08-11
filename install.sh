#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TMP_FILES=()
SKILLS_STAGING=""
REFUSED_OVERLAYS=()
WITHHELD_PATHS=()

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
	report_refusals
}
trap cleanup EXIT

# Emitted from the EXIT trap rather than the end of `main`, so a later unrelated hard
# failure cannot swallow it: the script still exits directly on a missing command, an
# unsafe managed path, a symlinked ancestor, an uncomparable payload or a missing
# source, and any of those during a later agent would preempt an end-of-run summary
# (ADR 0049). Silent when nothing was refused, so a clean run gains no output.
report_refusals() {
	local entry

	if [[ ${#REFUSED_OVERLAYS[@]} -eq 0 ]]; then
		return 0
	fi
	printf 'install: %s private overlay(s) were refused:\n' "${#REFUSED_OVERLAYS[@]}" >&2
	for entry in "${REFUSED_OVERLAYS[@]}"; do
		printf 'install:   %s\n' "$entry" >&2
	done
	if [[ ${#WITHHELD_PATHS[@]} -eq 0 ]]; then
		return 0
	fi
	# "left untouched", not "deployed ... kept as they are": an absent path is withheld and
	# listed here too, so a header claiming every entry is deployed would tell an operator
	# reading only the tail that a missing file is present and intact.
	printf 'install: these paths were left untouched:\n' >&2
	for entry in "${WITHHELD_PATHS[@]}"; do
		printf 'install:   %s\n' "$entry" >&2
	done
}

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
	printf '%s: %s added, %s updated, %s unchanged, %s pruned, %s retained\n' \
		"$agent" "$ADDED" "$UPDATED" "$UNCHANGED" "$PRUNED" "$RETAINED"
	printf '%s: manifest %s\n' "$agent" "$manifest"
}

start_agent() {
	MANIFEST_ENTRIES=()
	ADDED=0
	UPDATED=0
	UNCHANGED=0
	PRUNED=0
	RETAINED=0
}

# Every base path the overlay must not have erased, as newline-delimited dotted paths,
# empty when the merge preserved everything (ADR 0043).
#
# jq's `*` recurses into objects and replaces arrays, so an overlay naming a base array
# drops entries it never mentioned. The rule is stated over the merged result rather
# than over the overlay's shape: a non-empty base array must come through identical, and
# a non-empty base object must still be an object. Both are derived from the base on
# each call, so a base file that grows a guarded value is covered without an edit here.
#
# `getpath` raises a type error rather than returning null when an ancestor stopped
# being indexable — `{"hooks":"x"}` gives `Cannot index string with string "PreToolUse"`
# — so the lookup is guarded; an unguarded one would abort with jq's message naming
# neither the overlay nor the path. Only the outermost path of a mismatch is reported,
# or replacing `hooks` would name every array and object beneath it.
erased_base_paths() { # base merged
	jq -rn --slurpfile base "$1" --slurpfile merged "$2" '
		($base[0]) as $b | ($merged[0]) as $m
		| [ $b | paths as $p
		    | select(($b | getpath($p)) as $v
		             | ($v | type) as $t
		             | ($t == "array" or $t == "object") and ($v | length) > 0)
		    | select(($b | getpath($p)) as $v
		             | (try ($m | getpath($p)) catch null) as $after
		             | if ($v | type) == "array"
		               then $after != $v
		               else ($after | type) != "object"
		               end)
		    | $p ] as $bad
		| $bad
		| map(select(. as $p
		             | $bad
		             | any((length < ($p | length)) and ($p[0:length] == .))
		             | not))
		| map(map(tostring) | join("."))
		| .[]
	'
}

render_base() { # base output
	if ! jq '.' "$1" >"$2"; then
		printf 'install: could not read base settings: %s\n' "$1" >&2
		exit 1
	fi
}

# Refusal returns; every other failure exits. The distinction is load-bearing rather
# than tidy (ADR 0049): testing this function's status at the call site suppresses
# `set -e` for its whole body, so an unguarded jq failure would fall through into the
# comparison, find a truncated document missing every protected path, and accuse a
# blameless overlay of erasing all of them. `erased_base_paths` reports "nothing
# erased" and "I could not tell" with the same empty stdout, so it is guarded too — a
# comparison that did not run must never be read as one that found nothing.
merge_json_settings() {
	local base="$1"
	local overlay="$2"
	local output="$3"
	local erased
	local erased_path

	require_command jq
	if [[ ! -f "$overlay" ]]; then
		render_base "$base" "$output"
		printf 'install: no private overlay at %s\n' "$overlay"
		return 0
	fi

	if ! jq -s '.[0] * .[1]' "$base" "$overlay" >"$output"; then
		printf 'install: could not merge private overlay %s into %s\n' "$overlay" "$base" >&2
		exit 1
	fi
	if ! erased="$(erased_base_paths "$base" "$output")"; then
		printf 'install: could not compare the merged result against %s\n' "$base" >&2
		exit 1
	fi
	if [[ -z "$erased" ]]; then
		printf 'install: applied private overlay %s\n' "$overlay"
		return 0
	fi

	printf 'install: private overlay %s would erase values %s defines:\n' \
		"$overlay" "$base" >&2
	while IFS= read -r erased_path; do
		printf 'install:   %s\n' "$erased_path" >&2
	done <<<"$erased"
	printf 'install: an overlay may add keys and override scalars, but may not change\n' >&2
	printf 'install:   a non-empty array or replace a non-empty object (ADR 0043).\n' >&2
	# The merged result is guard-erased and fully formed, and `exit 1` used to make it
	# unreachable. Removing it keeps "no unguarded settings file is deployed" structural:
	# a call site that installs it anyway now fails on `install_managed_path`'s
	# missing-source check instead of deploying it under a green summary.
	unlink "$output"
	return 1
}

# Says what the file the agent actually loads holds right now. ADR 0043's refusal could
# only say the deployed file "may already be missing these values"; the installer holds
# the base and can read the file, so it says which. Reports and never writes, so a
# deliberate hand edit is named and left exactly as the operator wrote it.
report_deployed_state() { # dest_dir base rel
	local dest_dir="$1"
	local base="$2"
	local path="$dest_dir/$3"
	local base_json
	local deployed_json
	local missing
	local missing_path

	if [[ -L "$path" ]]; then
		# Occupied as far as `destination_set_is_empty` is concerned, so it is retained and
		# listed as kept — saying "nothing is deployed" here would contradict that in the
		# same output. What is not checked is the target, which the installer does not own.
		printf 'install: %s is a symlink; its target was not checked. A successful run\n' \
			"$path" >&2
		printf 'install:   replaces it as drift.\n' >&2
		return 0
	fi
	if [[ -d "$path" ]]; then
		# Occupied, like the symlink above: `destination_set_is_empty` counts it, so it is
		# retained and listed. "No file is deployed" would say the destination is bare
		# when something is sitting on it.
		printf 'install: a directory occupies %s; its contents were not inspected\n' \
			"$path" >&2
		return 0
	fi
	if [[ ! -f "$path" ]]; then
		printf 'install: no file is deployed at %s\n' "$path" >&2
		return 0
	fi

	base_json="$(jq -S '.' "$base")" || {
		printf 'install: could not read base settings: %s\n' "$base" >&2
		exit 1
	}
	# The one failure that is a verdict rather than an error: it describes the operator's
	# file, not the installer's machinery, so it is reported and the run continues.
	if ! deployed_json="$(jq -S '.' "$path" 2>/dev/null)"; then
		printf 'install: %s could not be read as JSON, so its contents were not checked\n' \
			"$path" >&2
		return 0
	fi
	if [[ "$base_json" == "$deployed_json" ]]; then
		printf 'install: %s is the base alone; no overlay of yours has ever been\n' "$path" >&2
		printf 'install:   applied there.\n' >&2
		return 0
	fi
	if ! missing="$(erased_base_paths "$base" "$path")"; then
		printf 'install: could not compare %s against %s\n' "$path" "$base" >&2
		exit 1
	fi
	if [[ -z "$missing" ]]; then
		# Say what was checked, not "carries every value". `erased_base_paths` is ADR
		# 0043's protected set — non-empty base arrays and objects — and it was designed
		# for a merge result, where jq's `*` cannot drop a base key. Pointed at an
		# arbitrary deployed file it no longer covers the base's scalar hardening, so an
		# unqualified affirmation would be a definite statement that is false, which is
		# worse than ADR 0043's hedge: the operator gets a reason to stop looking.
		printf 'install: %s has every array and object %s protects\n' "$path" "$base" >&2
		printf 'install:   Base scalars are outside this check and were not compared.\n' >&2
		return 0
	fi

	printf 'install: %s is missing protected values from %s:\n' "$path" "$base" >&2
	while IFS= read -r missing_path; do
		printf 'install:   %s\n' "$missing_path" >&2
	done <<<"$missing"
	printf 'install: fix or remove the overlay and re-run; the installer then replaces\n' >&2
	printf 'install:   that file and keeps the current one under\n' >&2
	printf 'install:   %s/.agent-config-backups/. If an earlier run replaced this file,\n' \
		"$dest_dir" >&2
	printf 'install:   its predecessor is there too.\n' >&2
}

retain_managed_path() { # dest_dir base rel
	local dest_dir="$1"
	local base="$2"
	local rel="$3"

	ensure_safe_rel "$rel"
	RETAINED=$((RETAINED + 1))
	# Recorded as managed even though nothing was written. A manifest that omits it tells
	# `prune_removed` to delete the deployed file, which would turn withholding a deploy
	# into deleting a deployment — the one way narrowing the abort could destroy operator
	# data (ADR 0049).
	MANIFEST_ENTRIES+=("$rel")
	WITHHELD_PATHS+=("$dest_dir/$rel")
	report_deployed_state "$dest_dir" "$base" "$rel"
}

destination_set_is_empty() { # dest_dir rel...
	local dest_dir="$1"
	local rel

	shift
	for rel in "$@"; do
		ensure_safe_rel "$rel"
		if [[ -e "$dest_dir/$rel" || -L "$dest_dir/$rel" ]]; then
			return 1
		fi
	done
	return 0
}

# One merged document can feed several destination paths — Bob's MCP output goes to both
# `mcp.json` and `mcp_settings.json` — so a refusal is handled over the whole set and
# never per path. Filling only the empty half of that pair would leave one logical
# document as two files with different contents (ADR 0049).
install_merged_json() { # dest_dir base overlay rel...
	local dest_dir="$1"
	local base="$2"
	local overlay="$3"
	local output
	local rel

	shift 3
	output="$(new_temp_file)"
	if merge_json_settings "$base" "$overlay" "$output"; then
		for rel in "$@"; do
			install_managed_path "$dest_dir" "$output" "$rel"
		done
		return 0
	fi

	# Recorded whichever way the destination is handled below: the run fails because the
	# overlay was refused, not because a path happened to be withheld. Filling an empty
	# destination from the base is still a refused overlay.
	REFUSED_OVERLAYS+=("$overlay")

	if destination_set_is_empty "$dest_dir" "$@"; then
		# Not a repair: nothing is overwritten and no running configuration is discarded.
		# What it settles is whether a fresh destination gets a guarded default or nothing
		# at all, beside an instruction tree that assumes the guards are there.
		printf 'install: nothing is deployed at these paths, so the base is installed\n' >&2
		printf 'install:   without your overlay; none of it applies until it is fixed.\n' >&2
		# A fresh 0600 temp file: the refusal unlinked the merged one, and re-creating it
		# by redirection would take the umask instead, deploying 0644. `payload_differs`
		# compares content and the executable bit only, so that mode would never converge.
		output="$(new_temp_file)"
		render_base "$base" "$output"
		for rel in "$@"; do
			install_managed_path "$dest_dir" "$output" "$rel"
		done
		return 0
	fi
	for rel in "$@"; do
		retain_managed_path "$dest_dir" "$base" "$rel"
	done
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
	# staged skills tree, which the same gate declares at directory granularity
	# rather than per file (ADR 0054). A fifth needs adding there too.
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

	start_agent
	dest_dir="$(canonical_dir "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"
	overlay_dir="$(private_overlay_dir claude "$host")"

	install_merged_json "$dest_dir" \
		"$REPO/agents/claude/shared/settings.base.json" \
		"$overlay_dir/settings.overlay.json" \
		"settings.json"
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
	local bob_modes

	start_agent
	dest_dir="$(canonical_dir "${BOB_CONFIG_DIR:-$HOME/.bob}")"
	overlay_dir="$(private_overlay_dir bob "$host")"
	bob_modes="$REPO/agents/bob/shared/custom_modes.yaml"

	validate_yaml_if_possible "$bob_modes"

	install_merged_json "$dest_dir" \
		"$REPO/agents/bob/shared/settings.base.json" \
		"$overlay_dir/settings.overlay.json" \
		"settings.json"
	install_merged_json "$dest_dir" \
		"$REPO/agents/bob/shared/mcp.json" \
		"$overlay_dir/mcp.overlay.json" \
		"mcp.json" "mcp_settings.json"
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

	# The refusal no longer ends the run, but it still fails it. `report_refusals` names
	# them from the EXIT trap; this is only the status.
	if [[ ${#REFUSED_OVERLAYS[@]} -ne 0 ]]; then
		exit 1
	fi
}

main "$@"
