#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'check-skill-layout-test: %s\n' "$*" >&2
	exit 1
}

assert_fails() {
	local expected="$1"
	local root="$2"
	local output
	local status

	set +e
	output="$(cd "$root" && bash scripts/check-skill-layout.sh 2>&1)"
	status="$?"
	set -e
	[[ "$status" -ne 0 ]] || fail "expected failure containing: $expected"
	printf '%s\n' "$output" | rg -Fq "$expected" ||
		fail "expected failure output to contain: $expected; got: $output"
}

write_skill() {
	local root="$1"
	local name="$2"
	local description="${3:-\"Fixture skill.\"}"

	mkdir -p "$root/content/skills/$name"
	printf '%s\n' \
		'---' \
		"name: $name" \
		"description: $description" \
		'---' \
		'' \
		'# Fixture' >"$root/content/skills/$name/SKILL.md"
}

new_fixture() {
	local root
	local index
	local name

	case_count="$(<"$counter_file")"
	case_count=$((case_count + 1))
	printf '%s\n' "$case_count" >"$counter_file"
	root="$workspace/case-$case_count"
	mkdir -p "$root/scripts" "$root/content/skills" "$root/agents/codex/shared"
	cp "$repo_root/scripts/check-skill-layout.sh" "$root/scripts/"
	cp "$repo_root/scripts/install-identity.sh" "$root/scripts/"
	cp "$repo_root/scripts/agent-skills-contract.json" "$root/scripts/"
	cp "$repo_root/scripts/reserved-skill-names.txt" "$root/scripts/"
	for index in {1..35}; do
		printf -v name 'skill-%02d' "$index"
		write_skill "$root" "$name"
	done
	printf '#!/usr/bin/env bash\nprintf "helper\\n"\n' \
		>"$root/content/skills/skill-01/helper.sh"
	chmod 755 "$root/content/skills/skill-01/helper.sh"
	printf '\n[Helper](helper.sh)\n[External](https://example.com/)\n' \
		>>"$root/content/skills/skill-01/SKILL.md"
	printf '%s\n' "$root"
}

replace_frontmatter() {
	local root="$1"
	shift
	printf '%s\n' "$@" '' '# Fixture' >"$root/content/skills/skill-01/SKILL.md"
}

assert_portable_userland() {
	local root="$1"
	local portable_bin="$root/portable-bin"

	mkdir -p "$portable_bin"
	# The wrapper source must contain the literal positional parameter.
	# shellcheck disable=SC2016
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'set -euo pipefail' \
		'for argument in "$@"; do' \
		'  case "$argument" in -mindepth|-maxdepth) exit 64 ;; esac' \
		'done' \
		"exec $system_find \"\$@\"" >"$portable_bin/find"
	# The wrapper source must contain the literal positional parameter.
	# shellcheck disable=SC2016
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'set -euo pipefail' \
		'for argument in "$@"; do' \
		'  case "$argument" in -i*) exit 64 ;; esac' \
		'done' \
		"exec $system_sed \"\$@\"" >"$portable_bin/sed"
	chmod 755 "$portable_bin/find" "$portable_bin/sed"
	(cd "$root" && PATH="$portable_bin:$PATH" bash scripts/check-skill-layout.sh)
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
implementation="$repo_root/scripts/check-skill-layout.sh"
contract="$repo_root/scripts/agent-skills-contract.json"
reserved="$repo_root/scripts/reserved-skill-names.txt"
system_find="$(command -v find)"
system_sed="$(command -v sed)"

[[ -x "$implementation" ]] || fail "implementation missing: $implementation"
[[ -f "$contract" ]] || fail "contract missing: $contract"
[[ -f "$reserved" ]] || fail "reserved names missing: $reserved"

workspace="$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-layout-test.XXXXXX")"
trap 'rm -R "$workspace"' EXIT
case_count=0
counter_file="$workspace/case-count"
printf '0\n' >"$counter_file"

bash "$implementation"

root="$(new_fixture)"
# This is a literal Markdown code-span fixture.
# shellcheck disable=SC2016
printf '\n`[Example](missing-example.md)\ncontinued example`\n' \
	>>"$root/content/skills/skill-01/SKILL.md"
# These are literal CommonMark code-span fixtures.
# shellcheck disable=SC2016
printf '%s\n' \
	'`` `[Double](missing-double.md)` ``' \
	'``` ``[Triple](missing-triple.md)`` ```' \
	'~~~~' \
	'[Fenced](missing-fenced.md)' \
	'~~~' \
	'[Still fenced](missing-still-fenced.md)' \
	'~~~~' \
	'[Helper reference][helper]' \
	'[External reference][external]' \
	'[Fragment reference][fragment]' \
	'[helper]: helper.sh' \
	'[external]: https://example.com/resource' \
	'[fragment]: #fixture' >>"$root/content/skills/skill-01/SKILL.md"
(cd "$root" && bash scripts/check-skill-layout.sh)
[[ -x "$root/content/skills/skill-01/helper.sh" ]] ||
	fail 'valid scan changed executable mode'

root="$(new_fixture)"
# The escaped delimiter is visible CommonMark text, not a code-span opener.
# shellcheck disable=SC2016
printf '%s\n' '\` [Broken](missing-escaped.md) `' \
	>>"$root/content/skills/skill-01/SKILL.md"
assert_fails \
	'content/skills/skill-01/SKILL.md: broken relative link: missing-escaped.md' \
	"$root"

root="$(new_fixture)"
printf '%s\n' \
	'' \
	'    [Space code](missing-space-code.md)' \
	$'\t[Tab code](missing-tab-code.md)' \
	>>"$root/content/skills/skill-01/SKILL.md"
(cd "$root" && bash scripts/check-skill-layout.sh)

root="$(new_fixture)"
printf '%s\n' \
	'' \
	'- item' \
	'    [Broken continuation](missing-list-continuation.md)' \
	>>"$root/content/skills/skill-01/SKILL.md"
assert_fails \
	'content/skills/skill-01/SKILL.md: broken relative link: missing-list-continuation.md' \
	"$root"

root="$(new_fixture)"
printf '%s\n' \
	'' \
	'- item' \
	'    [Helper continuation](helper.sh)' \
	'' \
	'      [Nested code](missing-list-code.md)' \
	>>"$root/content/skills/skill-01/SKILL.md"
(cd "$root" && bash scripts/check-skill-layout.sh)

root="$(new_fixture)"
assert_portable_userland "$root"

root="$(new_fixture)"
mkdir -p "$root/workflow-tree"
ln -s ../../workflow-tree "$root/agents/codex/tooling"
assert_fails 'agents/codex/tooling: native symlinks are forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/workflow-tree"
ln -s ../../workflow-tree "$root/agents/codex/commands"
assert_fails 'agents/codex/commands: native symlinks are forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/claude/shared/skills/native"
assert_fails 'agents/claude/shared/skills: native skill directory is forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/claude/shared/nested/commands"
printf 'workflow\n' >"$root/agents/claude/shared/nested/commands/native.md"
assert_fails 'agents/claude/shared/nested/commands/native.md: native command is forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/bob/shared/nested"
printf 'workflow\n' >"$root/agents/bob/shared/nested/SKILL.md"
assert_fails 'agents/bob/shared/nested/SKILL.md: native SKILL.md is forbidden' "$root"

root="$(new_fixture)"
printf 'workflow\n' >"$root/agents/codex/SKILL.md"
assert_fails 'agents/codex/SKILL.md: native SKILL.md is forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/codex/commands"
printf 'workflow\n' >"$root/agents/codex/commands/foo.md"
assert_fails 'agents/codex/commands/foo.md: native command is forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/codex/commands"
mkfifo "$root/agents/codex/commands/workflow"
assert_fails 'agents/codex/commands/workflow: native command is forbidden' "$root"

root="$(new_fixture)"
printf 'workflow\n' >"$root/workflow.md"
ln -s ../../workflow.md "$root/agents/codex/SKILL.md"
assert_fails 'agents/codex/SKILL.md: native SKILL.md is forbidden' "$root"

root="$(new_fixture)"
newline_name=$'bad\nname.md'
printf 'resource\n' >"$root/content/skills/skill-01/$newline_name"
assert_fails 'content/skills: path contains newline' "$root"

root="$(new_fixture)"
printf '%b' \
	'---\nname: skill-01\0\ndescription: "Fixture."\n---\n\n# Fixture\n' \
	>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'content/skills/skill-01/SKILL.md: NUL bytes are forbidden' "$root"

root="$(new_fixture)"
replace_frontmatter "$root" '---' 'name: skill-01' \
	'description: "Fixture."' 'description: "Duplicate."' '---'
assert_fails 'content/skills/skill-01/SKILL.md: frontmatter must be exactly four lines' "$root"

root="$(new_fixture)"
replace_frontmatter "$root" '---' 'name: skill-01' \
	'description: "Fixture."' 'vendor: value' '---'
assert_fails 'content/skills/skill-01/SKILL.md: frontmatter must be exactly four lines' "$root"

root="$(new_fixture)"
replace_frontmatter "$root" '---' 'name: skill-01' 'description: >-' '  Fixture.' '---'
assert_fails 'content/skills/skill-01/SKILL.md: frontmatter must be exactly four lines' "$root"

root="$(new_fixture)"
printf '\377' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'content/skills/skill-01/SKILL.md: file must be valid UTF-8' "$root"

root="$(new_fixture)"
replace_frontmatter "$root" '---' 'name: skill-01' 'description: ""' '---'
assert_fails \
	'content/skills/skill-01/SKILL.md: description must contain 1-1024 Unicode scalars' \
	"$root"

root="$(new_fixture)"
long_description="$(printf '%*s' 1025 '')"
long_description="${long_description// /x}"
replace_frontmatter "$root" '---' 'name: skill-01' \
	"description: \"$long_description\"" '---'
assert_fails \
	'content/skills/skill-01/SKILL.md: description must contain 1-1024 Unicode scalars' \
	"$root"

root="$(new_fixture)"
replace_frontmatter "$root" '---' 'name: "skill-01"' \
	'description: "Fixture."' '---'
assert_fails 'content/skills/skill-01/SKILL.md: name must be a plain canonical scalar' "$root"

root="$(new_fixture)"
mv "$root/content/skills/skill-01" "$root/content/skills/skill--01"
sed 's/name: skill-01/name: skill--01/' \
	"$root/content/skills/skill--01/SKILL.md" >"$root/name.tmp"
mv "$root/name.tmp" "$root/content/skills/skill--01/SKILL.md"
assert_fails 'content/skills/skill--01: invalid skill name' "$root"

root="$(new_fixture)"
printf '\n# test fixture\nskill-01\n' >>"$root/scripts/reserved-skill-names.txt"
assert_fails 'content/skills/skill-01: reserved skill name' "$root"

root="$(new_fixture)"
ln -s helper.sh "$root/content/skills/skill-01/helper-link"
assert_fails 'content/skills/skill-01/helper-link: symlinks are forbidden' "$root"

root="$(new_fixture)"
printf '\n[Missing](missing.md)\n' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'content/skills/skill-01/SKILL.md: broken relative link: missing.md' "$root"

root="$(new_fixture)"
printf '\n[Escape](../../outside.md)\n' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'content/skills/skill-01/SKILL.md: relative link escapes skill package' "$root"

root="$(new_fixture)"
printf '%s\n' '[Missing reference][missing]' '[missing]: missing-ref.md' \
	>>"$root/content/skills/skill-01/SKILL.md"
assert_fails \
	'content/skills/skill-01/SKILL.md: broken relative link: missing-ref.md' \
	"$root"

root="$(new_fixture)"
printf '%s\n' '[Escape reference][escape]' '[escape]: ../../outside.md' \
	>>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'content/skills/skill-01/SKILL.md: relative link escapes skill package' "$root"

root="$(new_fixture)"
printf '[Missing](missing-uppercase.md)\n' \
	>"$root/content/skills/skill-01/GUIDE.MD"
assert_fails \
	'content/skills/skill-01/GUIDE.MD: broken relative link: missing-uppercase.md' \
	"$root"

root="$(new_fixture)"
printf '[Escape](../../outside.md)\n' \
	>"$root/content/skills/skill-01/Guide.MaRkDoWn"
assert_fails \
	'content/skills/skill-01/Guide.MaRkDoWn: relative link escapes skill package' \
	"$root"

root="$(new_fixture)"
printf '\nUse ~/.codex/skills/skill-01/helper.sh.\n' \
	>>"$root/content/skills/skill-01/SKILL.md"
assert_fails \
	'content/skills/skill-01/SKILL.md: installed config-root reference is forbidden' \
	"$root"

root="$(new_fixture)"
printf 'upper\n' >"$root/content/skills/skill-01/Readme.md"
printf 'lower\n' >"$root/content/skills/skill-01/README.md"
assert_fails 'content/skills/skill-01/Readme.md: ASCII case-fold path collision' "$root"

root="$(new_fixture)"
printf 'non-ASCII\n' >"$root/content/skills/skill-01/café.md"
assert_fails 'content/skills/skill-01/café.md: non-ASCII path component' "$root"

root="$(new_fixture)"
write_skill "$root" skill-36
assert_fails 'content/skills: expected exactly 35 skill directories, found 36' "$root"

root="$(new_fixture)"
jq '.source.commit = "0000000000000000000000000000000000000000"' \
	"$root/scripts/agent-skills-contract.json" >"$root/scripts/contract.tmp"
mv "$root/scripts/contract.tmp" "$root/scripts/agent-skills-contract.json"
assert_fails 'scripts/agent-skills-contract.json: contract does not match pinned rules' "$root"

case_count="$(<"$counter_file")"
printf 'check-skill-layout-test: ok (%d adversarial fixtures)\n' "$case_count"
