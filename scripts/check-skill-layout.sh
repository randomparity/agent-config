#!/usr/bin/env bash
set -euo pipefail

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
		if [[ ! "$entry" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ || "$entry" == *--* ]]; then
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
		[[ "$component" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
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

	if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ||
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

root_pattern='(~|[$]HOME|[$][{]HOME[}])/[.](codex|claude|bob)(/|$)'
root_reference="$(rg -l "$root_pattern" "$skills_root" || true)"
[[ -z "$root_reference" ]] ||
	skill_error "${root_reference%%$'\n'*}" 'installed config-root reference is forbidden'

printf 'skills-check: ok (%s canonical skills, %s project review examples)\n' \
	"$count" "$project_review_count"
