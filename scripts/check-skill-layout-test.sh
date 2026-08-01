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
		fail "expected failure containing: $expected; got: $output"
	case_count=$((case_count + 1))
}

write_skill() {
	local root="$1"
	local name="$2"
	local body="${3:-# Test skill}"

	mkdir -p "$root/content/skills/$name"
	printf '%s\n' \
		'---' \
		"name: $name" \
		'description: "Test skill."' \
		'---' \
		"$body" >"$root/content/skills/$name/SKILL.md"
}

new_fixture() {
	local root

	root="$(mktemp -d "$tmpdir/case.XXXXXX")"
	mkdir -p "$root/scripts" "$root/agents/claude/shared" \
		"$root/agents/codex/shared" "$root/agents/bob/shared"
	cp "$implementation" "$root/scripts/check-skill-layout.sh"
	cp "$reserved" "$root/scripts/reserved-skill-names.txt"
	write_skill "$root" 'skill-01'
	printf '%s\n' "$root"
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
implementation="$repo_root/scripts/check-skill-layout.sh"
reserved="$repo_root/scripts/reserved-skill-names.txt"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/skill-layout-test.XXXXXX")"
trap 'rm -R "$tmpdir"' EXIT
case_count=0

output="$(cd "$repo_root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (35 canonical skills)' ]] || fail "$output"

root="$(new_fixture)"
mkdir -p "$root/content/skills/skill-01/scripts"
printf '#!/usr/bin/env bash\n' >"$root/content/skills/skill-01/scripts/run.sh"
chmod 755 "$root/content/skills/skill-01/scripts/run.sh"
(cd "$root" && bash scripts/check-skill-layout.sh >/dev/null)
[[ -x "$root/content/skills/skill-01/scripts/run.sh" ]] || fail 'guard changed file mode'

root="$(new_fixture)"
write_skill "$root" 'skill-02'
output="$(cd "$root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (2 canonical skills)' ]] || fail "$output"

root="$(new_fixture)"
mkdir -p "$root/agents/codex/nested"
printf '%s\n' 'workflow' >"$root/agents/codex/nested/SKILL.md"
assert_fails 'agents/codex/nested/SKILL.md: native SKILL.md is forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/claude/shared/commands"
printf '%s\n' 'workflow' >"$root/agents/claude/shared/commands/build.md"
assert_fails 'native command source is forbidden' "$root"

root="$(new_fixture)"
mkdir -p "$root/agents/bob/shared/skills/example"
assert_fails 'native skill source is forbidden' "$root"

root="$(new_fixture)"
ln -s ../../../content/skills "$root/agents/codex/shared/tooling"
assert_fails 'native symlinks are forbidden' "$root"

root="$(new_fixture)"
printf '%s\n' '---' 'name: skill-01' 'summary: wrong' '---' '# Body' \
	>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'description must be a one-line JSON string' "$root"

root="$(new_fixture)"
printf '%s\n' '---' 'name: wrong' 'description: "Test skill."' '---' '# Body' \
	>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'name must match its skill directory' "$root"

root="$(new_fixture)"
printf '%s\n' '---' 'name: skill-01' 'description: ""' '---' '# Body' \
	>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'description must contain 1-1024 Unicode scalars' "$root"

root="$(new_fixture)"
printf '%s\n' '---' 'name: skill-01' 'description: "Test skill."' '---' \
	>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'non-empty Markdown must follow frontmatter' "$root"

root="$(new_fixture)"
mv "$root/content/skills/skill-01" "$root/content/skills/plan"
printf '%s\n' '---' 'name: plan' 'description: "Test skill."' '---' '# Body' \
	>"$root/content/skills/plan/SKILL.md"
assert_fails 'content/skills/plan: reserved skill name' "$root"

root="$(new_fixture)"
ln -s SKILL.md "$root/content/skills/skill-01/link.md"
assert_fails 'content/skills/skill-01/link.md: symlinks are forbidden' "$root"

root="$(new_fixture)"
mkfifo "$root/content/skills/skill-01/runtime"
assert_fails 'only regular files and directories are allowed' "$root"

root="$(new_fixture)"
printf '%s\n' 'resource' >"$root/content/skills/skill-01/café.md"
assert_fails 'path component is not portable ASCII' "$root"

root="$(new_fixture)"
printf '%s\n' 'one' >"$root/content/skills/skill-01/Readme.md"
printf '%s\n' 'two' >"$root/content/skills/skill-01/readme.md"
assert_fails 'content/skills: ASCII case-fold path collision' "$root"

root="$(new_fixture)"
printf '%s\n' 'Use ~/.codex/skills here.' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'installed config-root reference is forbidden' "$root"

printf 'check-skill-layout-test: ok (%d focused failures)\n' "$case_count"
