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

validate_native_sources() {
	local agents="$1"
	local path
	local relative
	local tail

	[[ -d "$agents" ]] || return 0
	while IFS= read -r -d '' path; do
		relative="${path#"$repo_root"/}"
		tail="${relative#agents/}"
		if [[ "${relative##*/}" == 'SKILL.md' ]]; then
			skill_error "$relative" 'native SKILL.md is forbidden'
		fi
		if [[ -L "$path" ]]; then
			skill_error "$relative" 'native symlinks are forbidden'
		fi
		case "$tail" in
		commands/* | */commands/*) skill_error "$relative" 'native command is forbidden' ;;
		esac
		case "$tail" in
		skills | */skills | skills/* | */skills/*)
			skill_error "$relative" 'native skill directory is forbidden'
			;;
		esac
	done < <(find "$agents" ! -path "$agents" -print0)
}

validate_portable_entry() {
	local relative="$1"
	local path="$skills_root/$relative"
	local identity_output

	if [[ "$relative" == *$'\n'* ]]; then
		skill_error 'content/skills' 'path contains newline'
	fi
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
	while IFS= read -r -d '' path; do
		relative="${path#"$skills_root"/}"
		validate_portable_entry "$relative"
		folded="$(LC_ALL=C printf '%s' "$relative" | tr '[:upper:]' '[:lower:]')"
		while IFS=$'\t' read -r seen_folded seen_relative; do
			if [[ "$folded" == "$seen_folded" && "$relative" != "$seen_relative" ]]; then
				skill_error "content/skills/$relative" 'ASCII case-fold path collision'
			fi
		done <"$workspace/folded-paths"
		printf '%s\t%s\n' "$folded" "$relative" >>"$workspace/folded-paths"
	done < <(find "$skills_root" ! -path "$skills_root" -print0)
}

validate_frontmatter() {
	local file="$1"
	local skill_name="$2"
	local relative="content/skills/$skill_name/SKILL.md"
	local line1 line2 line3 line4 json lengths
	local without_nul="$workspace/without-nul-$skill_name"

	LC_ALL=C tr -d '\000' <"$file" >"$without_nul"
	if ! cmp -s "$without_nul" "$file"; then
		skill_error "$relative" 'NUL bytes are forbidden'
	fi
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

markdown_with_indentation_marks() {
	local markdown="$1"

	awk '
    function leading_columns(line, initial, position, character, columns) {
      columns = initial
      for (position = 1; position <= length(line); position++) {
        character = substr(line, position, 1)
        if (character == " ") columns++
        else if (character == "\t") columns += 4 - (columns % 4)
        else break
      }
      leading_characters = position - 1
      return columns
    }
    function list_marker_allowed(base, depth) {
      if (base <= 3) return 1
      for (depth = container_depth; depth >= 1; depth--) {
        if (base >= container_indents[depth] &&
            base - container_indents[depth] <= 3) return 1
      }
      return 0
    }
    function list_content_indent(line, base, candidate, separator, marker, padding) {
      base = leading_columns(line, 0)
      candidate = substr(line, leading_characters + 1)
      separator = match(candidate, /[ \t]/)
      if (separator == 0) {
        marker = candidate
        padding = 1
      } else marker = substr(candidate, 1, separator - 1)
      if (marker !~ /^[-+*]$/ &&
          (marker !~ /^[0-9]+[.)]$/ || length(marker) > 10)) return 0
      if (!list_marker_allowed(base)) return 0
      if (separator != 0) {
        padding = leading_columns(substr(candidate, separator), base + length(marker))
        padding -= base + length(marker)
        if (padding > 4) padding = 1
      }
      list_marker_indent = base
      return base + length(marker) + padding
    }
    {
      indentation = leading_columns($0, 0)
      content_indent = list_content_indent($0)
      indented_code = 0
      if (content_indent > 0) {
        while (container_depth > 0 &&
               list_marker_indent < container_indents[container_depth]) {
          delete container_indents[container_depth]
          container_depth--
        }
        container_indents[++container_depth] = content_indent
      } else if ($0 !~ /^[ \t]*$/) {
        while (container_depth > 0 &&
               indentation < container_indents[container_depth]) {
          delete container_indents[container_depth]
          container_depth--
        }
        if (container_depth > 0)
          indented_code = indentation - container_indents[container_depth] >= 4
        else indented_code = indentation >= 4
      }
      print (indented_code ? "1" : "0") $0
    }
  ' "$markdown"
}

markdown_visible_text() {
	local markdown="$1"

	markdown_with_indentation_marks "$markdown" | awk '
    function without_indent(line, count) {
      count = 0
      while (count < 3 && substr(line, count + 1, 1) == " ") count++
      return substr(line, count + 1)
    }
    function run_length(line, character, count) {
      count = 0
      while (substr(line, count + 1, 1) == character) count++
      return count
    }
    function opens_fence(line, candidate, character, run_size, rest) {
      candidate = without_indent(line)
      character = substr(candidate, 1, 1)
      if (character != "`" && character != "~") return 0
      run_size = run_length(candidate, character)
      if (run_size < 3) return 0
      rest = substr(candidate, run_size + 1)
      if (character == "`" && index(rest, "`") != 0) return 0
      fence_character = character
      fence_length = run_size
      return 1
    }
    function closes_fence(line, candidate, run_size, rest) {
      candidate = without_indent(line)
      if (substr(candidate, 1, 1) != fence_character) return 0
      run_size = run_length(candidate, fence_character)
      if (run_size < fence_length) return 0
      rest = substr(candidate, run_size + 1)
      return rest ~ /^[[:space:]]*$/
    }
    function code_run(line, position, run_size) {
      run_size = 0
      while (substr(line, position + run_size, 1) == "`") run_size++
      return run_size
    }
    function escaped_delimiter(line, position, slash_count) {
      slash_count = 0
      while (position - slash_count > 1 &&
             substr(line, position - slash_count - 1, 1) == "\\") {
        slash_count++
      }
      return slash_count % 2 == 1
    }
    function visible_line(line, position, start, run_size, text) {
      position = 1
      while (position <= length(line)) {
        text = substr(line, position)
        start = index(text, "`")
        if (start == 0) {
          if (code_length == 0) printf "%s", text
          else pending = pending text
          return
        }
        start += position - 1
        if (code_length == 0 && escaped_delimiter(line, start)) {
          printf "%s", substr(line, position, start - position + 1)
          position = start + 1
          continue
        }
        if (code_length == 0) printf "%s", substr(line, position, start - position)
        else pending = pending substr(line, position, start - position)
        run_size = code_run(line, start)
        if (code_length == 0) {
          code_length = run_size
          pending = substr(line, start, run_size)
        } else if (run_size == code_length) {
          code_length = 0
          pending = ""
        } else {
          pending = pending substr(line, start, run_size)
        }
        position = start + run_size
      }
    }
    {
      indented_code = substr($0, 1, 1) == "1"
      $0 = substr($0, 2)
      if (fence_character != "") {
        if (closes_fence($0)) {
          fence_character = ""
          fence_length = 0
        }
        next
      }
      if (code_length == 0 && indented_code) next
      if (code_length == 0 && opens_fence($0)) next
      visible_line($0)
      if (code_length == 0) printf "\n"
      else pending = pending "\n"
    }
    END { if (code_length != 0) printf "%s", pending }
  '
}

markdown_link_tokens() {
	local markdown="$1"

	markdown_visible_text "$markdown" | awk '
    function emit_destination(raw, end, fields) {
      sub(/^[[:space:]]*/, "", raw)
      if (substr(raw, 1, 1) == "<") {
        end = index(raw, ">")
        if (end == 0) return
        print substr(raw, 2, end - 2)
        return
      }
      split(raw, fields, /[[:space:]]+/)
      print fields[1]
    }
    {
      line = $0
      candidate = line
      for (indent = 0; indent < 3 && substr(candidate, 1, 1) == " "; indent++) {
        candidate = substr(candidate, 2)
      }
      if (match(candidate, /^\[[^]]+\]:[[:space:]]*/)) {
        emit_destination(substr(candidate, RLENGTH + 1))
      }
      while (match(line, /\]\([^)]*\)/)) {
        token = substr(line, RSTART + 2, RLENGTH - 3)
        emit_destination(token)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  '
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
	while IFS= read -r -d '' path; do
		validate_links "$skill_dir" "$path"
	done < <(find "$skill_dir" -type f \( -iname '*.md' -o -iname '*.markdown' \) -print0)
}

validate_inventory() {
	local path
	local count=0

	[[ -d "$skills_root" ]] || skill_error 'content/skills' 'canonical skill tree is missing'
	while IFS= read -r -d '' path; do
		[[ -d "$path" && ! -L "$path" ]] ||
			skill_error "${path#"$repo_root"/}" 'immediate children must be skill directories'
		count=$((count + 1))
	done < <(find "$skills_root" ! -path "$skills_root" -prune -print0)
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

while IFS= read -r -d '' skill_dir; do
	validate_skill "$skill_dir"
done < <(find "$skills_root" ! -path "$skills_root" -prune -type d -print0)

if root_reference="$(rg -l '(~|\$HOME|\$\{HOME\})/\.(codex|claude|bob)(/|$)' \
	"$skills_root" || :)" && [[ -n "$root_reference" ]]; then
	skill_error "${root_reference%%$'\n'*}" 'installed config-root reference is forbidden'
fi

printf 'skills-check: ok (35 canonical skills)\n'
