#!/usr/bin/env bash
set -euo pipefail

# Enumerated, not the ranges [a-z0-9] and [A-Za-z0-9]: a bash bracket expression
# takes its ranges from the locale's collation, so under en_US.UTF-8 -- the
# ordinary interactive locale -- [A-Za-z] admits accented letters. Written as a
# range the ASCII-portability rules below do not bite on the host that actually
# runs them, which is how `café.md` passed a check whose message says "portable
# ASCII" (ADR 0023 closed the same defect in tracker.sh). Pinning the collation
# instead would mean an `LC_ALL=C` subshell around every match, since a variable
# assignment cannot prefix the `[[` builtin. Do not "simplify" these back to
# ranges; `check-skill-layout-test.sh` fails if you do.
ascii_lower_digit='abcdefghijklmnopqrstuvwxyz0123456789'
ascii_alnum="ABCDEFGHIJKLMNOPQRSTUVWXYZ$ascii_lower_digit"
readonly ascii_lower_digit ascii_alnum

skill_error() {
	local path="$1"
	shift
	printf 'skills-check: %s: %s\n' "$path" "$*" >&2
	exit 1
}

validate_reserved_names() {
	local entry

	[[ -f "$reserved" ]] ||
		skill_error 'scripts/reserved-skill-names.txt' 'inventory is missing'
	while IFS= read -r entry || [[ -n "$entry" ]]; do
		case "$entry" in
		'' | \#*) continue ;;
		esac
		if [[ ! "$entry" =~ ^[$ascii_lower_digit]([$ascii_lower_digit-]*[$ascii_lower_digit])?$ ||
			"$entry" == *--* ]]; then
			skill_error 'scripts/reserved-skill-names.txt' "invalid name: $entry"
		fi
	done <"$reserved"
}

validate_native_sources() {
	local path
	local relative

	[[ -d "$repo_root/agents" ]] || return 0
	while IFS= read -r -d '' path; do
		relative="${path#"$repo_root/"}"
		[[ ! -L "$path" ]] || skill_error "$relative" 'native symlinks are forbidden'
		[[ "${path##*/}" != 'SKILL.md' ]] ||
			skill_error "$relative" 'native SKILL.md is forbidden'
		case "/$relative/" in
		*/commands/*) skill_error "$relative" 'native command source is forbidden' ;;
		*/skills/*) skill_error "$relative" 'native skill source is forbidden' ;;
		esac
	done < <(find "$repo_root/agents" ! -path "$repo_root/agents" -print0)
}

validate_example_skill_locations() {
	local path
	local relative

	[[ -d "$examples_root" ]] || return 0
	while IFS= read -r -d '' path; do
		relative="${path#"$examples_root/"}"
		if [[ -L "$path" && -d "$path" ]]; then
			skill_error "examples/$relative" 'directory symlinks are forbidden'
		fi
		[[ "${path##*/}" == 'SKILL.md' ]] || continue
		[[ "$relative" =~ ^project-review-skills/[^/]+/SKILL\.md$ ]] ||
			skill_error "examples/$relative" \
				'SKILL.md is allowed only under examples/project-review-skills'
	done < <(find "$examples_root" \( -type l -o -type f -name SKILL.md \) -print0)
}

validate_relative_path() {
	local relative="$1"
	local inventory="$2"
	local component
	local byte_length
	local -a components

	byte_length="$(
		LC_ALL=C
		printf '%s' "$relative" | wc -c | tr -d ' '
	)"
	[[ "$byte_length" -le 512 ]] || skill_error "$inventory/$relative" 'path is too long'
	IFS='/' read -r -a components <<<"$relative"
	for component in "${components[@]}"; do
		byte_length="$(
			LC_ALL=C
			printf '%s' "$component" | wc -c | tr -d ' '
		)"
		[[ "$byte_length" -ge 1 && "$byte_length" -le 100 ]] ||
			skill_error "$inventory/$relative" 'path component length must be 1-100 bytes'
		[[ "$component" =~ ^[$ascii_alnum][$ascii_alnum._-]*$ ]] ||
			skill_error "$inventory/$relative" 'path component is not portable ASCII'
		[[ "$component" != *. ]] ||
			skill_error "$inventory/$relative" 'path component must not end in a dot'
	done
}

validate_portable_tree() {
	local inventory_root="$1"
	local inventory="$2"
	local missing_message="$3"
	local path
	local relative
	local folded
	local duplicate

	[[ -d "$inventory_root" ]] || skill_error "$inventory" "$missing_message"
	: >"$workspace/paths"
	while IFS= read -r -d '' path; do
		relative="${path#"$inventory_root/"}"
		[[ ! -L "$path" ]] || skill_error "$inventory/$relative" 'symlinks are forbidden'
		[[ -f "$path" || -d "$path" ]] ||
			skill_error "$inventory/$relative" 'only regular files and directories are allowed'
		validate_relative_path "$relative" "$inventory"
		folded="$(LC_ALL=C printf '%s' "$relative" | tr '[:upper:]' '[:lower:]')"
		printf '%s\t%s\n' "$folded" "$relative" >>"$workspace/paths"
	done < <(find "$inventory_root" ! -path "$inventory_root" -print0)
	duplicate="$(LC_ALL=C sort "$workspace/paths" | cut -f1 | uniq -d | sed -n '1p')"
	[[ -z "$duplicate" ]] || skill_error "$inventory" 'ASCII case-fold path collision'
}

validate_frontmatter() {
	local skill_dir="$1"
	local inventory="$2"
	local name="${skill_dir##*/}"
	local file="$skill_dir/SKILL.md"
	local relative="$inventory/$name/SKILL.md"
	local line1 line2 line3 line4 description

	[[ -f "$file" && ! -L "$file" ]] ||
		skill_error "$relative" 'required regular file is missing'
	iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1 ||
		skill_error "$relative" 'file must be valid UTF-8'
	line1="$(sed -n '1p' "$file")"
	line2="$(sed -n '2p' "$file")"
	line3="$(sed -n '3p' "$file")"
	line4="$(sed -n '4p' "$file")"
	[[ "$line1" == '---' && "$line4" == '---' ]] ||
		skill_error "$relative" 'frontmatter must be exactly four lines'
	[[ "$line2" == "name: $name" ]] ||
		skill_error "$relative" 'name must match its skill directory'
	[[ "$line3" == 'description: "'* ]] ||
		skill_error "$relative" 'description must be a one-line JSON string'
	description="${line3#description: }"
	printf '%s' "$description" | jq -e \
		'type == "string" and length >= 1 and length <= 1024' >/dev/null 2>&1 ||
		skill_error "$relative" 'description must contain 1-1024 Unicode scalars'
	sed -n '5,$p' "$file" | rg -q '[^[:space:]]' ||
		skill_error "$relative" 'non-empty Markdown must follow frontmatter'
}

validate_skill() {
	local skill_dir="$1"
	local inventory="$2"
	local name="${skill_dir##*/}"

	if [[ ! "$name" =~ ^[$ascii_lower_digit]([$ascii_lower_digit-]*[$ascii_lower_digit])?$ ||
		"$name" == *--* || ${#name} -gt 64 ]]; then
		skill_error "$inventory/$name" 'invalid skill name'
	fi
	if rg -Fxq "$name" "$reserved"; then
		skill_error "$inventory/$name" 'reserved skill name'
	fi
	validate_frontmatter "$skill_dir" "$inventory"
}

validate_inventory() {
	local inventory_root="$1"
	local inventory="$2"
	local missing_message="$3"
	local empty_message="$4"
	local skill_dir
	local count=0

	[[ -d "$inventory_root" ]] || skill_error "$inventory" "$missing_message"
	while IFS= read -r -d '' skill_dir; do
		[[ -d "$skill_dir" && ! -L "$skill_dir" ]] ||
			skill_error "${skill_dir#"$repo_root/"}" 'children must be skill directories'
		validate_skill "$skill_dir" "$inventory"
		count=$((count + 1))
	done < <(find "$inventory_root" ! -path "$inventory_root" -prune -print0)
	[[ "$count" -gt 0 ]] || skill_error "$inventory" "$empty_message"
	printf '%s\n' "$count"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
reserved="$script_dir/reserved-skill-names.txt"
skills_root="$repo_root/content/skills"
examples_root="$repo_root/examples"
project_review_root="$repo_root/examples/project-review-skills"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-check.XXXXXX")"
trap 'rm -R "$workspace"' EXIT

validate_reserved_names
validate_native_sources
validate_example_skill_locations
validate_portable_tree "$skills_root" 'content/skills' 'canonical tree is missing'
validate_portable_tree "$project_review_root" 'examples/project-review-skills' \
	'project review tree is missing'
count="$(validate_inventory "$skills_root" 'content/skills' 'canonical tree is missing' \
	'canonical tree is empty')"
project_review_count="$(validate_inventory "$project_review_root" \
	'examples/project-review-skills' 'project review tree is missing' \
	'project review tree is empty')"

# A deployment rule (ADR 0004) — deployed content must resolve its own assets
# rather than name an installed client's config root — so it scans every content
# root the installer copies: `content/skills`, plus the `content/languages` and
# `content/references` that `install_common_content` delivers to all three agents
# as the same bytes. `testdata` entries are excluded exactly as `stage_skills`
# excludes them (ADR 0025); the portability checks above still cover them, because
# those are repository hygiene rather than delivery.
#
# `agents/*/shared` is deliberately not scanned: an agent's own instructions may
# name that agent's own config root, and `CLAUDE.md` and `AGENTS.md` legitimately do.
# Two scans, because ripgrep's globs filter the whole traversal rather than the
# path argument they follow. `content/skills` is the only root `stage_skills`
# filters; `content/languages` and `content/references` deploy verbatim, so a
# `testdata` entry under either really does ship and must stay visible here.
root_pattern='(~|[$]HOME|[$][{]HOME[}])/[.](codex|claude|bob)(/|$)'

# `|| true` below cannot distinguish "no matches" (rg exit 1) from "that root is
# gone" (exit 2, diagnostic on stderr), so a rename that outruns this script would
# leave the gate reporting ok having scanned nothing. Fail closed first, the way
# check-deployed-references.sh does for the same roots.
for common_root in \
	"$repo_root/content/languages" \
	"$repo_root/content/references"; do
	[[ -d "$common_root" ]] ||
		skill_error "${common_root#"$repo_root/"}" 'deployed content root is missing'
done

root_reference="$(
	rg -l --glob '!testdata' --glob '!testdata/**' \
		"$root_pattern" "$skills_root" || true
	rg -l "$root_pattern" "$repo_root/content/languages" \
		"$repo_root/content/references" || true
)"
[[ -z "$root_reference" ]] ||
	skill_error "${root_reference%%$'\n'*}" 'installed config-root reference is forbidden'

printf 'skills-check: ok (%s canonical skills, %s project review examples)\n' \
	"$count" "$project_review_count"
