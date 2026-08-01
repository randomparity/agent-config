#!/usr/bin/env bash
set -euo pipefail

skill_error() {
	local path="$1"
	shift
	printf 'skills-check: %s: %s\n' "$path" "$*" >&2
	exit 1
}

validate_contract() {
	local contract="$1"

	[[ -f "$contract" ]] || skill_error 'scripts/agent-skills-contract.json' 'contract is missing'
	jq -e '
    keys == ["description", "frontmatter", "name", "path", "source"] and
    .source == {
      "commit": "38a2ff82958afee88dadf4831509e6f7e9d8ef4e",
      "specification_blob": "20cf9f6b672391e3295733c7863480905de6b887"
    } and
    .frontmatter == {"allowed_keys": ["description", "name"]} and
    .name == {
      "min_unicode_scalars": 1,
      "max_unicode_scalars": 64,
      "pattern": "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
      "forbid_consecutive_hyphens": true
    } and
    .description == {"min_unicode_scalars": 1, "max_unicode_scalars": 1024} and
    .path == {
      "component_min_bytes": 1,
      "component_max_bytes": 100,
      "max_bytes": 512,
      "component_pattern": "^[A-Za-z0-9][A-Za-z0-9._-]*$",
      "ascii_only": true,
      "forbid_component_trailing_dot": true,
      "case_fold_unique": true
    }
  ' "$contract" >/dev/null 2>&1 ||
		skill_error 'scripts/agent-skills-contract.json' 'contract does not match pinned rules'
}

validate_reserved_names() {
	local reserved="$1"
	local entry

	[[ -f "$reserved" ]] || skill_error 'scripts/reserved-skill-names.txt' 'inventory is missing'
	while IFS= read -r entry || [[ -n "$entry" ]]; do
		case "$entry" in
		'' | \#*) continue ;;
		esac
		[[ "$entry" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] &&
			[[ "$entry" != *--* ]] ||
			skill_error 'scripts/reserved-skill-names.txt' "invalid reserved name: $entry"
	done <"$reserved"
}

native_tail() {
	local relative="$1"
	local tail="${relative#agents/}"

	printf '%s\n' "${tail#*/shared/}"
}

validate_native_sources() {
	local agents="$1"
	local path
	local relative
	local tail

	[[ -d "$agents" ]] || return 0
	while IFS= read -r path; do
		relative="${path#"$repo_root"/}"
		[[ "$relative" =~ ^agents/[^/]+/shared/ ]] || continue
		tail="$(native_tail "$relative")"
		if [[ "${tail##*/}" == 'SKILL.md' ]]; then
			skill_error "$relative" 'native SKILL.md is forbidden'
		fi
		case "/$tail/" in
		*/commands/*) skill_error "$relative" 'native command is forbidden' ;;
		esac
	done < <(find "$agents" -type f -print | LC_ALL=C sort)

	while IFS= read -r path; do
		relative="${path#"$repo_root"/}"
		[[ "$relative" =~ ^agents/[^/]+/shared/ ]] || continue
		tail="$(native_tail "$relative")"
		case "/$tail/" in
		*/skills/*) skill_error "$relative" 'native skill directory is forbidden' ;;
		esac
	done < <(find "$agents" -type d -print | LC_ALL=C sort)
}

validate_portable_entry() {
	local relative="$1"
	local path="$skills_root/$relative"
	local identity_output

	if [[ -L "$path" ]]; then
		skill_error "content/skills/$relative" 'symlinks are forbidden'
	fi
	if [[ ! -d "$path" && ! -f "$path" ]]; then
		skill_error "content/skills/$relative" 'only regular files and directories are allowed'
	fi
	if ! identity_output="$(require_portable_rel "$relative" 2>&1)"; then
		skill_error "content/skills/$relative" "${identity_output#identity: }"
	fi
}

validate_portable_tree() {
	local path
	local relative
	local folded
	local seen_folded
	local seen_relative

	: >"$workspace/folded-paths"
	while IFS= read -r path; do
		relative="${path#"$skills_root"/}"
		validate_portable_entry "$relative"
		folded="$(LC_ALL=C printf '%s' "$relative" | tr '[:upper:]' '[:lower:]')"
		while IFS=$'\t' read -r seen_folded seen_relative; do
			if [[ "$folded" == "$seen_folded" && "$relative" != "$seen_relative" ]]; then
				skill_error "content/skills/$relative" 'ASCII case-fold path collision'
			fi
		done <"$workspace/folded-paths"
		printf '%s\t%s\n' "$folded" "$relative" >>"$workspace/folded-paths"
	done < <(find "$skills_root" -mindepth 1 -print | LC_ALL=C sort)
}

validate_frontmatter() {
	local file="$1"
	local skill_name="$2"
	local relative="content/skills/$skill_name/SKILL.md"
	local line1 line2 line3 line4 json lengths

	iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1 ||
		skill_error "$relative" 'file must be valid UTF-8'
	line1="$(sed -n '1p' "$file")"
	line2="$(sed -n '2p' "$file")"
	line3="$(sed -n '3p' "$file")"
	line4="$(sed -n '4p' "$file")"
	[[ "$line1" == '---' && "$line4" == '---' ]] ||
		skill_error "$relative" 'frontmatter must be exactly four lines'
	[[ "$line2" =~ ^name:\ ([a-z0-9][a-z0-9-]*[a-z0-9]|[a-z0-9])$ ]] ||
		skill_error "$relative" 'name must be a plain canonical scalar'
	[[ "${line2#name: }" == "$skill_name" ]] ||
		skill_error "$relative" 'name must match its skill directory'
	[[ "$line3" == 'description: "'* ]] ||
		skill_error "$relative" 'description must be a one-line JSON string'
	json="${line3#description: }"
	if ! lengths="$(printf '%s' "$json" | jq -er \
		'if type == "string" then length else error("not a string") end' 2>/dev/null)"; then
		skill_error "$relative" 'description must be a one-line JSON string'
	fi
	[[ "$lengths" != *$'\n'* && "$lengths" =~ ^[0-9]+$ &&
		"$lengths" -ge 1 && "$lengths" -le 1024 ]] ||
		skill_error "$relative" 'description must contain 1-1024 Unicode scalars'
	sed -n '5,$p' "$file" | rg -q '[^[:space:]]' ||
		skill_error "$relative" 'non-empty Markdown must follow frontmatter'
}

markdown_link_tokens() {
	local markdown="$1"

	awk '
    /^[[:space:]]*(```|~~~)/ { fenced = !fenced; next }
    !fenced {
      output = ""
      rest = $0
      while (match(rest, /`/)) {
        if (!inline) output = output substr(rest, 1, RSTART - 1)
        inline = !inline
        rest = substr(rest, RSTART + 1)
      }
      if (!inline) output = output rest
      print output
    }
  ' "$markdown" | rg --no-filename -o '\]\([^)]*\)' || :
}

validate_links() {
	local skill_dir="$1"
	local markdown="$2"
	local relative="${markdown#"$repo_root"/}"
	local link
	local target
	local markdown_dir

	markdown_dir="$(dirname "$markdown")"
	while IFS= read -r link; do
		target="${link#']('}"
		target="${target%')'}"
		case "$target" in
		'' | \#* | http://* | https://* | mailto:*) continue ;;
		/* | file:*) skill_error "$relative" "relative link escapes skill package: $target" ;;
		esac
		target="${target%%#*}"
		target="${target%%\?*}"
		while [[ "$target" == ./* ]]; do target="${target#./}"; done
		case "/$target/" in
		*/../*) skill_error "$relative" 'relative link escapes skill package' ;;
		esac
		[[ -e "$markdown_dir/$target" ]] ||
			skill_error "$relative" "broken relative link: $target"
		case "$(cd "$(dirname "$markdown_dir/$target")" && pwd -P)/$(basename "$target")" in
		"$skill_dir"/*) ;;
		*) skill_error "$relative" 'relative link escapes skill package' ;;
		esac
	done < <(markdown_link_tokens "$markdown")
}

validate_skill() {
	local skill_dir="$1"
	local name="${skill_dir##*/}"
	local name_pattern
	local path

	name_pattern="$(jq -r '.name.pattern' "$contract")"
	[[ "$name" =~ $name_pattern && "$name" != *--* && ${#name} -le 64 ]] ||
		skill_error "content/skills/$name" 'invalid skill name'
	rg -Fxq "$name" "$reserved" &&
		skill_error "content/skills/$name" 'reserved skill name'
	[[ -f "$skill_dir/SKILL.md" && ! -L "$skill_dir/SKILL.md" ]] ||
		skill_error "content/skills/$name/SKILL.md" 'required regular file is missing'
	validate_frontmatter "$skill_dir/SKILL.md" "$name"
	while IFS= read -r path; do
		validate_links "$skill_dir" "$path"
	done < <(find "$skill_dir" -type f -name '*.md' -print | LC_ALL=C sort)
}

validate_inventory() {
	local path
	local count=0

	[[ -d "$skills_root" ]] || skill_error 'content/skills' 'canonical skill tree is missing'
	while IFS= read -r path; do
		[[ -d "$path" && ! -L "$path" ]] ||
			skill_error "${path#"$repo_root"/}" 'immediate children must be skill directories'
		count=$((count + 1))
	done < <(find "$skills_root" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
	[[ "$count" -eq 35 ]] ||
		skill_error 'content/skills' "expected exactly 35 skill directories, found $count"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
contract="$script_dir/agent-skills-contract.json"
reserved="$script_dir/reserved-skill-names.txt"
skills_root="$repo_root/content/skills"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-check.XXXXXX")"
trap 'rm -R "$workspace"' EXIT

# shellcheck source=install-identity.sh
# Resolved from this script's checked-in directory.
# shellcheck disable=SC1091
source "$script_dir/install-identity.sh"

validate_contract "$contract"
validate_reserved_names "$reserved"
validate_native_sources "$repo_root/agents"
validate_inventory
validate_portable_tree

while IFS= read -r skill_dir; do
	validate_skill "$skill_dir"
done < <(find "$skills_root" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)

if root_reference="$(rg -l '(~|\$HOME|\$\{HOME\})/\.(codex|claude|bob)(/|$)' \
	"$skills_root" || :)" && [[ -n "$root_reference" ]]; then
	skill_error "${root_reference%%$'\n'*}" 'installed config-root reference is forbidden'
fi

printf 'skills-check: ok (35 canonical skills)\n'
