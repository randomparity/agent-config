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

# Carries the same one-object test the merge makes, because this is the other way a base
# reaches a destination: with no overlay present at all, and on ADR 0049's empty-destination
# fill. A bare `jq '.'` emits both documents of a two-document base and passes `[]` straight
# through, so a malformed base would deploy verbatim under a green run and the file the
# agent loads would be missing every guard the base defines (ADR 0052).
render_base() { # base output
	if ! jq -s --arg base "$1" '
		if length == 1 and (.[0] | type) == "object" then .[0]
		else error("base settings \($base) are not exactly one JSON object")
		end
	' "$1" >"$2"; then
		printf 'install: could not read base settings: %s\n' "$1" >&2
		exit 1
	fi
}

# `<document count><TAB><type of the sole document>`; the type is empty unless the count
# is 1. `-s` slurps the file's whole *value stream*, which is exactly the property the
# merge below relies on and cannot see: a file holding two objects yields 2 here and
# reaches `.[1]` as one there.
overlay_shape() { # overlay
	jq -s -r '[length, (if length == 1 then (.[0] | type) else "" end)] | @tsv' "$1"
}

# Same three things the protected-key refusal says — name the overlay, say what is wrong,
# say what to do — for the shapes that used to abort the run with a raw jq message naming
# the base's contents and no remedy (ADR 0052). Never names the base: the operator's file
# is the subject of every one of these.
report_overlay_shape() { # overlay problem remedy...
	local overlay="$1"
	local problem="$2"
	local line

	shift 2
	printf 'install: private overlay %s %s\n' "$overlay" "$problem" >&2
	for line in "$@"; do
		printf 'install:   %s\n' "$line" >&2
	done
	printf 'install: an overlay must be exactly one JSON object (ADR 0052).\n' >&2
}

# Returns non-zero for a refusal, and prints the verdict that goes with it. The caller
# treats that exactly as it treats a protected-key refusal, so a malformed overlay
# withholds the destination set the merge feeds and nothing else (ADR 0049).
#
# A failure of `overlay_shape` itself is read as "this file is not JSON". jq's exit status
# does not separate an unparseable input from a broken jq, and the check's whole subject is
# the operator's file — the same call `report_deployed_state` already makes about a
# deployed file. Either way it is a refusal, so nothing derived from the overlay is
# written; and a jq that is genuinely broken fails `render_base` on the next line with its
# own message.
overlay_is_one_object() { # overlay
	local overlay="$1"
	local shape
	local count
	local kind
	local bytes
	local text_bytes

	# The two checks below this one are byte-level on purpose. The shape check reads the
	# overlay through jq, which is the same reader the merge uses, so it can only ever
	# confirm that reader's own blind spots — a file jq truncates identically in both places
	# is reported as sound in both places. Each of these is a thing jq's answer cannot
	# disagree with, and both are shapes where jq's answer is wrong (ADR 0052).
	#
	# jq's lexer stops at a NUL, so `{"a":1}\000{"b":2}` slurps to *one* object: the shape
	# check passes it, the merge reads the same one document, and the second object is
	# discarded on a green `applied private overlay` — precisely the defect this precondition
	# exists to close. It also catches UTF-16 and UTF-32, which are full of NUL bytes and
	# would otherwise be reported as containing no JSON value at all.
	#
	# Redirection failures are discarded like the tool stderr below: an unreadable overlay
	# would otherwise print bash's own `Permission denied` ahead of the verdict. It then
	# reads as zero-length and unchanged by `tr`, and falls through to the shape check,
	# which is the one that reports it.
	bytes="$({ wc -c <"$overlay"; } 2>/dev/null)"
	text_bytes="$({ tr -d '\000' <"$overlay" | wc -c; } 2>/dev/null)"
	if [[ "$bytes" -ne "$text_bytes" ]]; then
		report_overlay_shape "$overlay" 'contains a NUL byte, so it is not UTF-8 JSON text' \
			'jq stops reading at the NUL, so anything after it is silently discarded. The' \
			'file is either corrupt or saved as UTF-16 or UTF-32; re-save it as UTF-8.'
		return 1
	fi

	# Ahead of the shape check, because the shape check cannot see it. jq strips a UTF-8
	# byte-order mark only at offset 0 of its concatenated input stream, so an overlay
	# carrying one parses cleanly when jq reads it alone and fails as the merge's *second*
	# input: the check would pass the file and the merge would abort the run with the raw
	# parse error this whole precondition exists to remove. It gets a verdict of its own
	# rather than folding into the one below, because `jq . <overlay>` — the remedy that
	# verdict prints — succeeds on it and shows the operator a well-formed object. Its stderr
	# is discarded like `overlay_shape`'s below, or an unreadable overlay would print
	# `head: cannot open ...` ahead of the verdict — the raw tool message this replaces.
	if [[ "$(head -c 3 "$overlay" 2>/dev/null)" == $'\357\273\277' ]]; then
		report_overlay_shape "$overlay" 'begins with a UTF-8 byte-order mark' \
			'The mark is invisible in an editor and jq accepts the file on its own, but' \
			'the merge reads it second and stops there. Save the file as UTF-8 with no BOM.'
		return 1
	fi

	if ! shape="$(overlay_shape "$overlay" 2>/dev/null)"; then
		report_overlay_shape "$overlay" 'is not valid JSON' \
			"Run: jq . '$overlay'"
		return 1
	fi
	IFS=$'\t' read -r count kind <<<"$shape" || true

	if [[ "$count" -eq 0 ]]; then
		report_overlay_shape "$overlay" 'contains no JSON value' \
			'An empty or whitespace-only file is not an overlay. Delete it to install' \
			'the base alone, or write a JSON object into it.'
		return 1
	fi
	if [[ "$count" -gt 1 ]]; then
		report_overlay_shape "$overlay" "contains $count JSON values, not one" \
			'Everything after the first would be discarded. Merge them into a single' \
			'JSON object.'
		return 1
	fi
	if [[ "$kind" != object ]]; then
		report_overlay_shape "$overlay" "is a JSON $kind, not an object" \
			'Its top-level value must be an object, such as {"env": {"KEY": "value"}}.'
		return 1
	fi
	return 0
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

	# Before the merge, because `.[1]` below reads one document out of a stream and cannot
	# report what it left behind (ADR 0052).
	if ! overlay_is_one_object "$overlay"; then
		unlink "$output"
		return 1
	fi

	# `-s` slurps *both* files into one array, so `.[1]` is the overlay only while the base
	# is one document too: a two-document base would push the overlay to `.[2]` and merge
	# the base with itself, under a green `applied private overlay`. This test is what makes
	# `.[1]` correct rather than accidentally correct, and it is a hard failure rather
	# than a refusal because the base is this repository's file — a malformed one is a defect
	# here, not a mistake the operator can fix (ADR 0052).
	if ! jq -s --arg base "$base" '
		if length == 2 and (.[0] | type) == "object" then .[0] * .[1]
		else error("base settings \($base) are not exactly one JSON object")
		end
	' "$base" "$overlay" >"$output"; then
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

# Bookkeeping only, and silent: each format reports what is live in its own terms, so the
# caller makes that call. It prints nothing itself, so moving the report out changes no
# output or its order.
retain_managed_path() { # dest_dir rel
	local dest_dir="$1"
	local rel="$2"

	ensure_safe_rel "$rel"
	RETAINED=$((RETAINED + 1))
	# Recorded as managed even though nothing was written. A manifest that omits it tells
	# `prune_removed` to delete the deployed file, which would turn withholding a deploy
	# into deleting a deployment — the one way narrowing the abort could destroy operator
	# data (ADR 0049).
	MANIFEST_ENTRIES+=("$rel")
	WITHHELD_PATHS+=("$dest_dir/$rel")
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
		retain_managed_path "$dest_dir" "$rel"
		report_deployed_state "$dest_dir" "$base" "$rel"
	done
}

# Read on stdin rather than as an operand. POSIX awk treats an operand matching
# `name=value` as a variable assignment, so an overlay whose path contains an `=` made awk
# read *stdin*, print nothing and exit 0 — the overlay silently dropped under a green
# `applied private overlay`, which is the one thing the status guard below exists to catch
# and the one shape it could not see. A redirection also fails loudly on an unreadable file.
emit_root_settings() {
	awk '
    /^[[:space:]]*\[/ { in_table = 1 }
    !in_table { print }
  ' <"$1"
}

emit_table_settings() {
	awk '
    /^[[:space:]]*\[/ { in_table = 1 }
    in_table { print }
  ' <"$1"
}

supports_tomllib() {
	command -v python3 >/dev/null 2>&1 &&
		python3 -c 'import tomllib' >/dev/null 2>&1
}

# With no overlay there is nothing to hoist, so the base is copied rather than run through
# the splitter. That makes one byte sequence "the base alone" — this file — which the
# ADR 0049 fill reuses and `report_deployed_toml_state` recognises with `cmp`. Splitting it
# produced a leading blank line, so a no-overlay run and an empty-overlay run deployed
# different bytes for the same meaning (ADR 0057 rule 3).
render_base_toml() { # base output
	if ! cp "$1" "$2"; then
		printf 'install: could not read base config: %s\n' "$1" >&2
		exit 1
	fi
}

# The base reaches a destination on three routes — no overlay at all, the ADR 0049 fill, and
# concatenated with an overlay — and only the third one used to be parsed, as part of the
# merged document. So a malformed base deployed verbatim on the default route under a green
# run, and blamed the operator's overlay on the third. A hard failure rather than a refusal,
# because this is the repository's file: a malformed one is a defect here, not a mistake the
# operator can fix (the same split `render_base` makes for JSON). Where no parser exists the
# base is trusted unread, which is what ADR 0057 rule 2 already says about it.
require_valid_base_toml() { # base
	local diagnostic
	local status=0

	diagnostic="$(validate_toml "$1")" || status=$?
	case "$status" in
	0 | 2) return 0 ;;
	1)
		printf 'install: base config %s is not valid TOML:\n' "$1" >&2
		printf 'install:   %s\n' "$diagnostic" >&2
		exit 1
		;;
	*)
		printf 'install: could not validate base config: %s\n' "$1" >&2
		exit 1
		;;
	esac
}

# `0` accepted, `1` rejected, `2` no parser here, `3` the validator itself failed. The
# diagnostic goes to stdout without the path: the caller holds the operator's overlay path,
# and the path this actually parses is a temporary file whose name is gone by the time the
# verdict is read (ADR 0057 rule 4).
#
# Reads bytes rather than text. `read_text()` decodes with the locale encoding, so a legal
# UTF-8 overlay raises `UnicodeDecodeError` under a non-UTF-8 `LC_ALL` — and under rule 2
# that would be a permanent refusal of a sound file, reported as a Python traceback. TOML
# 1.0 mandates UTF-8 and `tomllib.load` decodes it.
validate_toml() { # path
	local path="$1"
	local status=0

	if ! supports_tomllib; then
		return 2
	fi
	python3 - "$path" <<'PY' || status=$?
import sys
import tomllib

# What is enumerated here is the *machine* failure -- an OSError reaching the file -- and
# everything else is a verdict about the operator's bytes. Enumerating it the other way
# round was wrong twice: `tomllib.load` decodes the file itself, so a latin-1 file raises
# `UnicodeDecodeError` rather than `TOMLDecodeError`, and it parses integers with
# `int(s, 0)`, so a number past Python's 4300-digit conversion limit raises a bare
# `ValueError`. Each of those printed a traceback and took the whole run down -- the abort
# ADR 0049 removed, reached from a file the operator can fix. The catch-all is the safe
# direction and the precedent is ADR 0052 rule 4, which reads a failure of the JSON shape
# check as a bad overlay for the same reason: the result is a refusal, so nothing derived
# from the overlay is written either way.
try:
    with open(sys.argv[1], "rb") as handle:
        tomllib.load(handle)
except OSError as exc:
    # Not a verdict about the contents -- the caller reports it and stops -- but it travels
    # as a message rather than as a traceback.
    sys.stdout.write(f"{exc}\n")
    raise SystemExit(3) from exc
except tomllib.TOMLDecodeError as exc:
    sys.stdout.write(f"{exc}\n")
    raise SystemExit(2) from exc
except UnicodeDecodeError as exc:
    sys.stdout.write(
        f"it is not UTF-8 text ({exc.reason}, at byte {exc.start}). TOML 1.0 requires"
        " UTF-8; re-save the file in that encoding.\n"
    )
    raise SystemExit(2) from exc
except RecursionError as exc:
    sys.stdout.write("it nests too deeply for the TOML parser to read.\n")
    raise SystemExit(2) from exc
except Exception as exc:
    sys.stdout.write(f"the TOML parser could not read it: {type(exc).__name__}: {exc}\n")
    raise SystemExit(2) from exc
PY
	case "$status" in
	0) return 0 ;;
	2) return 1 ;;
	*) return 3 ;;
	esac
}

# Every base path the merged document does not carry with an equal value, as
# newline-delimited dotted paths, empty when the merge preserved everything (ADR 0057).
#
# Stated over the parse rather than over the overlay's text, because the hoist below is
# `awk` matching `^[[:space:]]*\[` and is not a TOML lexer: an overlay that opens a
# multi-line string in its root section has its tail relocated behind the base's tables,
# *inside* that string, and the base's tables are swallowed without the overlay naming
# anything. No check over names can see that; the parse can.
#
# The selector is every base value, where `erased_base_paths` takes only non-empty arrays
# and objects. jq's `*` cannot drop a base key, so the JSON rule could leave scalars to it.
# Concatenation reconciles nothing and drops whatever the splitter moved, so a scalar needs
# covering too — and this base is one scalar.
erased_base_toml_paths() { # base merged
	python3 - "$1" "$2" <<'PY'
import sys
import tomllib


def load(path):
    with open(path, "rb") as handle:
        return tomllib.load(handle)


# Only the outermost path of a mismatch, or a swallowed table would name every key beneath
# it as well as itself. `type` is compared alongside value because TOML's booleans and
# integers compare equal in Python — `True == 1` — and `goals = 1` is not `goals = true`.
def walk(base, merged, trail, found):
    for key, value in base.items():
        path = trail + [key]
        if not isinstance(merged, dict) or key not in merged:
            found.append(path)
            continue
        after = merged[key]
        if isinstance(value, dict):
            if isinstance(after, dict):
                walk(value, after, path, found)
            else:
                found.append(path)
        elif after != value or type(after) is not type(value):
            found.append(path)


try:
    base = load(sys.argv[1])
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"install: base config {sys.argv[1]} is not valid TOML: {exc}")
found = []
walk(base, load(sys.argv[2]), [], found)
for path in found:
    print(".".join(path))
PY
}

# Guarded individually rather than run as one `{ ... } >"$output"` group. `awk` exits
# non-zero on an unreadable overlay, and this whole body runs with `set -e` suppressed
# because the caller tests the status — so an unguarded failure would contribute nothing
# and read as a merge that preserved everything (ADR 0049 rule 1).
emit_merged_toml() { # base overlay
	emit_root_settings "$1" &&
		printf '\n' &&
		emit_root_settings "$2" &&
		printf '\n' &&
		emit_table_settings "$1" &&
		printf '\n' &&
		emit_table_settings "$2"
}

report_toml_overlay() { # overlay problem remedy...
	local overlay="$1"
	local problem="$2"
	local line

	shift 2
	printf 'install: private overlay %s %s\n' "$overlay" "$problem" >&2
	for line in "$@"; do
		printf 'install:   %s\n' "$line" >&2
	done
}

# Returns 0 when the merged document is deployable and 1 when the overlay is refused.
# Every other failure exits, and the distinction is load-bearing rather than tidy (ADR 0049
# rule 1): testing this function's status at the call site suppresses `set -e` for its whole
# body, so an unguarded failure anywhere below would fall through into the comparison and
# either accuse a blameless overlay or, worse, report a comparison that never ran as one
# that found nothing.
merge_toml_config() { # base overlay output
	local base="$1"
	local overlay="$2"
	local output="$3"
	local diagnostic
	local erased
	local erased_path
	local status=0

	require_valid_base_toml "$base"

	if [[ ! -f "$overlay" ]]; then
		render_base_toml "$base" "$output"
		printf 'install: no private overlay at %s\n' "$overlay"
		return 0
	fi

	# The overlay is read on its own before the hoist touches it, because the hoist's reader
	# cannot be trusted to reach a verdict about it. `awk` is locale-sensitive: the awk on
	# macOS aborts on a byte sequence that is not valid in the current locale — `towc:
	# multibyte conversion failure` — and exits non-zero, so a latin-1 overlay never reached
	# the parser there and took the whole run down as an unreadable file, while on Linux the
	# same file reached `tomllib` and got a verdict. This is ADR 0052's lesson in the other
	# direction: the check has to run ahead of a reader that cannot express the answer.
	#
	# It also sharpens the two verdicts below. Everything that survives this parses on its
	# own, so a merged document that does not parse, or that lost a base value, is the
	# hoist's doing and can be reported as such without hedging.
	diagnostic="$(validate_toml "$overlay")" || status=$?
	case "$status" in
	0) ;;
	1)
		report_toml_overlay "$overlay" 'is not valid TOML:' \
			"$diagnostic" \
			"Run: python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],\"rb\"))' \\" \
			"  '$overlay'"
		unlink "$output"
		return 1
		;;
	2)
		report_toml_overlay "$overlay" 'cannot be applied here' \
			'Applying it means checking that it preserves what the base defines, and that' \
			'check is a TOML parse. This host has no python3 that can import tomllib,' \
			'which needs Python 3.11 or newer; install one and re-run. The base alone is' \
			'all the installer can deploy until then (ADR 0057).'
		unlink "$output"
		return 1
		;;
	*)
		printf 'install: could not read private overlay %s\n' "$overlay" >&2
		if [[ -n "$diagnostic" ]]; then
			printf 'install:   %s\n' "$diagnostic" >&2
		fi
		exit 1
		;;
	esac

	if ! emit_merged_toml "$base" "$overlay" >"$output"; then
		printf 'install: could not merge private overlay %s into %s\n' "$overlay" "$base" >&2
		exit 1
	fi

	status=0
	diagnostic="$(validate_toml "$output")" || status=$?
	case "$status" in
	0) ;;
	1)
		# Two causes reach here and they need different remedies, so neither is asserted.
		# The common one is a duplicate declaration: TOML forbids declaring a table or key
		# twice, and an overlay that names one the base already defines is the only way to
		# reach a base value at all. The other is the hoist mangling a legal file. Leading
		# with the wrong one sends the operator to the wrong file.
		report_toml_overlay "$overlay" 'does not survive the merge:' \
			"$diagnostic" \
			'Your overlay parses on its own, so the merge is what produced this, and the' \
			'positions above are in the merged document rather than in your file. Either it' \
			'declares a table or key the base already defines -- TOML forbids declaring one' \
			'twice, so an overlay may add but not redefine -- or a root value that opens a' \
			'multi-line string or array swallowed the base tables, in which case put that' \
			'value inside a table of its own.'
		unlink "$output"
		return 1
		;;
	*)
		printf 'install: could not validate the merged TOML for %s\n' "$overlay" >&2
		exit 1
		;;
	esac

	if ! erased="$(erased_base_toml_paths "$base" "$output")"; then
		printf 'install: could not compare the merged result against %s\n' "$base" >&2
		exit 1
	fi
	if [[ -n "$erased" ]]; then
		printf 'install: merging private overlay %s loses values %s defines:\n' \
			"$overlay" "$base" >&2
		while IFS= read -r erased_path; do
			printf 'install:   %s\n' "$erased_path" >&2
		done <<<"$erased"
		printf 'install: an overlay may add tables and keys, but every value the base\n' >&2
		printf 'install:   defines must survive the merge unchanged (ADR 0057).\n' >&2
		# The overlay already parsed on its own above, so it did not write anything wrong and
		# the merge's hoist is what lost the value. Saying "your overlay may not erase this"
		# would blame a legal file for the installer's own splitting, and this is the shape
		# that motivated ADR 0057, so it gets the cause rather than the rule.
		printf 'install: your overlay is valid TOML on its own, so this is the merge\n' >&2
		printf 'install:   splitting it: root settings are moved above the base tables, and\n' >&2
		printf 'install:   a root value that opens a multi-line string or array swallows\n' >&2
		printf 'install:   them. Put that value inside a table of its own and re-run.\n' >&2
		unlink "$output"
		return 1
	fi

	# After the result is accepted, not before it is checked: printed first, this line
	# appeared on every run that then went on to fail.
	printf 'install: applied private overlay %s\n' "$overlay"
	return 0
}

# The TOML counterpart of `report_deployed_state`, and deliberately weaker. ADR 0049 rule 5
# names which protected base values a deployed file still carries; that is a parse, and the
# refusal this reports on may be a refusal *because* there is no parser. What survives
# without one is a byte comparison against the base, which answers the one question that
# matters most — whether any overlay of theirs has ever applied here.
report_deployed_toml_state() { # dest_dir base rel
	local dest_dir="$1"
	local base="$2"
	local path="$dest_dir/$3"

	if [[ -L "$path" ]]; then
		printf 'install: %s is a symlink; its target was not checked. A successful run\n' \
			"$path" >&2
		printf 'install:   replaces it as drift.\n' >&2
		return 0
	fi
	if [[ -d "$path" ]]; then
		printf 'install: a directory occupies %s; its contents were not inspected\n' \
			"$path" >&2
		return 0
	fi
	if [[ ! -f "$path" ]]; then
		printf 'install: no file is deployed at %s\n' "$path" >&2
		return 0
	fi
	if cmp -s "$base" "$path"; then
		printf 'install: %s is the base alone; no overlay of yours has ever been\n' "$path" >&2
		printf 'install:   applied there.\n' >&2
		return 0
	fi

	printf 'install: %s differs from the base and was left exactly as it is; its\n' \
		"$path" >&2
	printf 'install:   contents were not checked against %s, which needs a TOML parse.\n' \
		"$base" >&2
	printf 'install: fix or remove the overlay and re-run; the installer then replaces\n' >&2
	printf 'install:   that file and keeps the current one under\n' >&2
	printf 'install:   %s/.agent-config-backups/.\n' "$dest_dir" >&2
}

# One destination path rather than `install_merged_json`'s set: Codex has one TOML file and
# no TOML document feeds two, so ADR 0049's whole-set handling has nothing to range over.
install_merged_toml() { # dest_dir base overlay rel
	local dest_dir="$1"
	local base="$2"
	local overlay="$3"
	local rel="$4"
	local output

	output="$(new_temp_file)"
	if merge_toml_config "$base" "$overlay" "$output"; then
		install_managed_path "$dest_dir" "$output" "$rel"
		return 0
	fi

	REFUSED_OVERLAYS+=("$overlay")

	if destination_set_is_empty "$dest_dir" "$rel"; then
		printf 'install: nothing is deployed at that path, so the base is installed\n' >&2
		printf 'install:   without your overlay; none of it applies until it is fixed.\n' >&2
		# A fresh 0600 temp file: the refusal unlinked the merged one, and re-creating it by
		# redirection would take the umask instead.
		output="$(new_temp_file)"
		render_base_toml "$base" "$output"
		install_managed_path "$dest_dir" "$output" "$rel"
		return 0
	fi
	retain_managed_path "$dest_dir" "$rel"
	report_deployed_toml_state "$dest_dir" "$base" "$rel"
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

	start_agent
	dest_dir="$(canonical_dir "${CODEX_CONFIG_DIR:-$HOME/.codex}")"
	overlay_dir="$(private_overlay_dir codex "$host")"

	install_merged_toml "$dest_dir" \
		"$REPO/agents/codex/shared/config.base.toml" \
		"$overlay_dir/config.overlay.toml" \
		"config.toml"
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
