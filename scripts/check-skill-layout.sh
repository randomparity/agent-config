#!/usr/bin/env bash
set -euo pipefail

# Every rule that reads file contents runs through rg, and two of them read a
# non-zero exit as a clean result: `if rg -Fxq` below takes 127 for "not
# reserved", and the config-root scan took it for "no matches". An absent rg
# would therefore pass this gate rather than fail it, so refuse up front the way
# check-deployed-references.sh does.
#
# Present is not enough, so every rg call below also carries --no-config: rg reads
# RIPGREP_CONFIG_PATH before its own arguments, and a developer's personal config
# then decides what these rules match. `--fixed-strings` alone breaks the gate in
# both directions at once -- the UTF-8 grammar becomes a literal that matches no
# line, so every skill file reads as malformed, and the config-root patterns become
# literals that match nothing, so a real violation reports clean. The rule holds for
# this gate only so far -- the sibling gate scripts in the same `just verify` chain
# are still steerable, and issue #119 tracks sweeping them.
if ! command -v rg >/dev/null 2>&1; then
	printf 'skills-check: rg is required\n' >&2
	exit 2
fi

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

# The UTF-8 rule below used to shell out to `iconv -f UTF-8 -t UTF-8`. Apple's CLI
# reads its input in fixed-size chunks and batches conversions across them, and
# rejects some well-formed files by where their multi-byte characters land rather
# than by what those characters are: the macOS leg failed a skill file that GNU
# iconv, `isutf8` and Python all accept, under a message naming the wrong cause
# (issue #101). `iconv` was an undeclared prerequisite besides. rg decides it
# instead -- this script already refuses to run without rg, `install-tools.sh`
# declares it, and both CI legs install the same binary, so the rule now costs no
# dependency the gate did not already have and answers the same on either.
#
# Unicode table 3-7 written as bytes, one alternative per well-formed sequence.
# The narrow lead and trail ranges are the substance, not decoration: they are what
# rejects overlong encodings (no \xC0-\xC1; \xE0 needs \xA0-\xBF; \xF0 needs
# \x90-\xBF), UTF-16 surrogates (\xED stops at \x9F) and scalars above U+10FFFF
# (\xF4 stops at \x8F; no \xF5-\xFF). GNU iconv accepts that last class, so a
# faithful port of the old behaviour would have been laxer than its own message.
utf8_scalar='[\x00-\x7F]'
utf8_scalar+='|[\xC2-\xDF][\x80-\xBF]'
utf8_scalar+='|\xE0[\xA0-\xBF][\x80-\xBF]'
utf8_scalar+='|[\xE1-\xEC][\x80-\xBF]{2}'
utf8_scalar+='|\xED[\x80-\x9F][\x80-\xBF]'
utf8_scalar+='|[\xEE-\xEF][\x80-\xBF]{2}'
utf8_scalar+='|\xF0[\x90-\xBF][\x80-\xBF]{2}'
utf8_scalar+='|[\xF1-\xF3][\x80-\xBF]{3}'
utf8_scalar+='|\xF4[\x80-\x8F][\x80-\xBF]{2}'
# `(?-u)` is what lets the classes name raw bytes; the anchors make the match the
# whole line rather than some well-formed run inside it.
utf8_line="(?-u)^(?:$utf8_scalar)*\$"
readonly utf8_scalar utf8_line

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

# rg splits on the line terminator before matching, and a terminator byte cannot
# occur inside a well-formed sequence -- so "every line is a run of well-formed
# sequences" is exactly "the file is well-formed UTF-8", and a sequence truncated at
# end of line fails the anchors instead of running into the next line.
#
# --encoding none turns off the BOM sniffing that would otherwise transcode a UTF-16
# file and report its bytes as valid UTF-8. --text disables binary detection, which
# triggers on a single NUL byte: for a file named explicitly it converts rather than
# quits, so the verdict survives without the flag but the reported position does not.
#
# The message names the offending line, because the failure it replaces cost hours
# for want of one. --max-count 1 keeps the early exit --quiet used to give. The line
# goes to a file rather than a command substitution on purpose: the bytes that failed
# may include a NUL, which bash drops from a substitution with a warning on stderr,
# and a guardrail should not emit one. sed takes the number and leaves the bytes --
# under LC_ALL=C, because the line it is trimming is by definition not decodable in a
# UTF-8 locale, and there `.*` stops at the first bad byte and drags it into the
# message (ADR 0023's defect in a new place).
validate_utf8() {
	local file="$1"
	local relative="$2"
	local status=0
	local bad_line

	rg --text --encoding none --no-config --invert-match --line-number --max-count 1 \
		--no-filename -- "$utf8_line" "$file" \
		>"$workspace/utf8-bad" 2>"$workspace/utf8-error" || status=$?
	# 0 = a line that is not well-formed, 1 = every line is, 2+ = no scan happened.
	case "$status" in
	0)
		bad_line="$(LC_ALL=C sed -n '1s/:.*//p' "$workspace/utf8-bad")"
		skill_error "$relative" "file must be valid UTF-8 (first malformed line $bad_line)"
		;;
	1) ;;
	*) skill_error "$relative" "UTF-8 scan failed: $(<"$workspace/utf8-error")" ;;
	esac
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
	validate_utf8 "$file" "$relative"
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
	sed -n '5,$p' "$file" | rg --no-config -q '[^[:space:]]' ||
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
	if rg --no-config -Fxq "$name" "$reserved"; then
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

# rg exits 2 for every scan it could not complete -- an unreadable file, a bad
# pattern, a root that vanished mid-run -- and the `|| true` this replaces
# reported all of those as "no matches found", so the gate printed ok having
# scanned nothing. Keep rg's diagnostics on their own stream instead of folding
# them in with `2>&1`: mixed into the match list a warning line parses as a
# result, and the gate reports it as a violation on a successful scan.
#
# --hidden --no-ignore is not optional: rg skips dot-prefixed and gitignored files
# by default, but install.sh stages skills with `cp -pR`, which copies both. Without
# these the scan set is narrower than the delivery set, and a dot-prefixed file
# under content/skills/ would ship to users unscanned while this gate printed ok.
# They belong here rather than at the call sites so the two rules cannot drift.
#
# --text is the same argument one step further: rg skips a file it decides is binary
# during traversal, and it decides that on a single NUL byte, so a forbidden
# config-root reference anywhere in a file carrying one is invisible and the gate
# reports clean. Every file these roots deliver today is text, so the flag only costs
# reading an asset that would otherwise be skipped -- the direction a gate should err
# in, since the alternative is a delivery the scan never saw.
#
# --encoding none closes the same hole through the other door. rg sniffs a leading
# UTF-16 BOM and transcodes on the strength of two bytes, so a UTF-8 file that merely
# begins \xFF\xFE is decoded as UTF-16, and the reference the scan is looking for
# comes out as mojibake that matches nothing. Reading raw bytes is also what
# validate_utf8 does, so both rules now see the file the installer will copy.
#
# That is a trade, not a free win: a file under these roots that really is UTF-16 was
# transcoded and scanned before and is opaque to this rule now. Nothing gates the
# encoding of `content/languages` or `content/references` -- only SKILL.md is checked
# -- so neither reading is safe for a genuine UTF-16 delivery, and the spoof is the
# reachable half. Issue #127 tracks giving those roots an encoding rule of their own.
scan_config_roots() { # results-file rg-argument...
	local results="$1"
	local status=0
	shift

	rg --no-config --text --encoding none -l --hidden --no-ignore "$@" >>"$results" \
		2>"$workspace/rg-error" || status=$?
	# 0 = matches, 1 = no matches, anything else = the scan did not happen.
	[[ "$status" -le 1 ]] ||
		skill_error 'content' "config-root scan failed: $(<"$workspace/rg-error")"
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
root_pattern='(~|[$]HOME|[$][{]HOME[}])/[.](codex|claude|bob|superpowers)(/|$)'

# Repo-relative agent state, the sibling of the rule above. That one catches
# `~/.codex/skills`; this catches `.codex/campaigns/x.md`, the shape that named one
# agent's directory in content projected into all three.
#
# A bare root passes, and must: three skills name `.codex/` as where a harness's
# native worktree tool nests a worktree, and `campaign` notes that many target repos
# track it. Those are true statements about a real harness, not paths this content
# writes. So "bare" is decided by the byte after the slash, and the class spells out
# every terminator a mention can end on -- backtick and close-paren both occur live,
# and a naive `[^[:space:]]` would reject all of them, since the prose is Markdown and
# most of these sit in code spans. The alternation is anchored on the slash, which is
# what keeps the real `.codex-plugin/plugin.json` out rather than the terminator set.
repo_pattern='[.](codex|claude|bob|superpowers)/[^[:space:]`,)"'"'"']'

# A missing root is caught here rather than left to `scan_config_roots`, so the
# gate names the root that went away instead of quoting rg's diagnostic for it.
for common_root in \
	"$repo_root/content/languages" \
	"$repo_root/content/references"; do
	[[ -d "$common_root" ]] ||
		skill_error "${common_root#"$repo_root/"}" 'deployed content root is missing'
done

: >"$workspace/root-references"
scan_config_roots "$workspace/root-references" \
	--glob '!testdata' --glob '!testdata/**' "$root_pattern" "$skills_root"
scan_config_roots "$workspace/root-references" "$root_pattern" \
	"$repo_root/content/languages" "$repo_root/content/references"
root_reference="$(sed -n '1p' "$workspace/root-references")"
[[ -z "$root_reference" ]] ||
	skill_error "$root_reference" 'installed config-root reference is forbidden'

# A separate results file, not a second pattern into the one above: sharing the sink
# would report a repo-relative hit under the home-rooted rule's message, naming
# neither the rule that fired nor the remedy.
: >"$workspace/repo-references"
scan_config_roots "$workspace/repo-references" \
	--glob '!testdata' --glob '!testdata/**' "$repo_pattern" "$skills_root"
scan_config_roots "$workspace/repo-references" "$repo_pattern" \
	"$repo_root/content/languages" "$repo_root/content/references"
repo_reference="$(sed -n '1p' "$workspace/repo-references")"
[[ -z "$repo_reference" ]] ||
	skill_error "$repo_reference" \
		'repo-relative agent state path is forbidden; move it under .agent/'

printf 'skills-check: ok (%s canonical skills, %s project review examples)\n' \
	"$count" "$project_review_count"
