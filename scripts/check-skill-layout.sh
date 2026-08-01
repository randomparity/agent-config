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

validate_relative_path() {
	local relative="$1"
	local component
	local byte_length
	local -a components

	byte_length="$(
		LC_ALL=C
		printf '%s' "$relative" | wc -c | tr -d ' '
	)"
	[[ "$byte_length" -le 512 ]] || skill_error "content/skills/$relative" 'path is too long'
	IFS='/' read -r -a components <<<"$relative"
	for component in "${components[@]}"; do
		byte_length="$(
			LC_ALL=C
			printf '%s' "$component" | wc -c | tr -d ' '
		)"
		[[ "$byte_length" -ge 1 && "$byte_length" -le 100 ]] ||
			skill_error "content/skills/$relative" 'path component length must be 1-100 bytes'
		[[ "$component" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
			skill_error "content/skills/$relative" 'path component is not portable ASCII'
		[[ "$component" != *. ]] ||
			skill_error "content/skills/$relative" 'path component must not end in a dot'
	done
}

validate_portable_tree() {
	local path
	local relative
	local folded
	local duplicate

	[[ -d "$skills_root" ]] || skill_error 'content/skills' 'canonical tree is missing'
	: >"$workspace/paths"
	while IFS= read -r -d '' path; do
		relative="${path#"$skills_root/"}"
		[[ ! -L "$path" ]] || skill_error "content/skills/$relative" 'symlinks are forbidden'
		[[ -f "$path" || -d "$path" ]] ||
			skill_error "content/skills/$relative" 'only regular files and directories are allowed'
		validate_relative_path "$relative"
		folded="$(LC_ALL=C printf '%s' "$relative" | tr '[:upper:]' '[:lower:]')"
		printf '%s\t%s\n' "$folded" "$relative" >>"$workspace/paths"
	done < <(find "$skills_root" ! -path "$skills_root" -print0)
	duplicate="$(LC_ALL=C sort "$workspace/paths" | cut -f1 | uniq -d | sed -n '1p')"
	[[ -z "$duplicate" ]] || skill_error 'content/skills' 'ASCII case-fold path collision'
}

validate_frontmatter() {
	local skill_dir="$1"
	local name="${skill_dir##*/}"
	local file="$skill_dir/SKILL.md"
	local relative="content/skills/$name/SKILL.md"
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
	local name="${skill_dir##*/}"

	if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ||
		"$name" == *--* || ${#name} -gt 64 ]]; then
		skill_error "content/skills/$name" 'invalid skill name'
	fi
	if rg -Fxq "$name" "$reserved"; then
		skill_error "content/skills/$name" 'reserved skill name'
	fi
	validate_frontmatter "$skill_dir"
}

validate_inventory() {
	local skill_dir
	local count=0

	[[ -d "$skills_root" ]] || skill_error 'content/skills' 'canonical tree is missing'
	while IFS= read -r -d '' skill_dir; do
		[[ -d "$skill_dir" && ! -L "$skill_dir" ]] ||
			skill_error "${skill_dir#"$repo_root/"}" 'children must be skill directories'
		validate_skill "$skill_dir"
		count=$((count + 1))
	done < <(find "$skills_root" ! -path "$skills_root" -prune -print0)
	[[ "$count" -gt 0 ]] || skill_error 'content/skills' 'canonical tree is empty'
	printf '%s\n' "$count"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
reserved="$script_dir/reserved-skill-names.txt"
skills_root="$repo_root/content/skills"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-check.XXXXXX")"
trap 'rm -R "$workspace"' EXIT

validate_reserved_names
validate_native_sources
validate_portable_tree
count="$(validate_inventory)"

root_pattern='(~|[$]HOME|[$][{]HOME[}])/[.](codex|claude|bob)(/|$)'
root_reference="$(rg -l "$root_pattern" "$skills_root" || true)"
[[ -z "$root_reference" ]] ||
	skill_error "${root_reference%%$'\n'*}" 'installed config-root reference is forbidden'

printf 'skills-check: ok (%s canonical skills)\n' "$count"
