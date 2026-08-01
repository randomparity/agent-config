#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'check-skill-layout-test: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local expected="$1"
	local file="$2"

	rg -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
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
	local inventory="$2"
	local name="$3"
	local body="${4:-# Test skill}"

	mkdir -p "$root/$inventory/$name"
	printf '%s\n' \
		'---' \
		"name: $name" \
		'description: "Test skill."' \
		'---' \
		"$body" >"$root/$inventory/$name/SKILL.md"
}

new_fixture() {
	local root

	root="$(mktemp -d "$tmpdir/case.XXXXXX")"
	mkdir -p "$root/scripts" "$root/agents/claude/shared" \
		"$root/agents/codex/shared" "$root/agents/bob/shared"
	cp "$implementation" "$root/scripts/check-skill-layout.sh"
	cp "$reserved" "$root/scripts/reserved-skill-names.txt"
	write_skill "$root" 'content/skills' 'skill-01'
	write_skill "$root" 'examples/project-review-skills' 'accessibility-reviewer'
	printf '%s\n' "$root"
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
implementation="$repo_root/scripts/check-skill-layout.sh"
reserved="$repo_root/scripts/reserved-skill-names.txt"
tmp_base="${TMPDIR:-/tmp}"
tmpdir="$(mktemp -d "$tmp_base/skill-layout-test.XXXXXX")"
[[ "$tmpdir" == "$tmp_base"/skill-layout-test.* ]] ||
	fail "fixtures must be created under $tmp_base"
trap 'rm -R "$tmpdir"' EXIT
case_count=0

example_skill="$repo_root/examples/project-review-skills/accessibility-reviewer/SKILL.md"
bob_instructions="$repo_root/examples/bob-project/AGENTS.md"
legacy_bob_skill="$repo_root/examples/bob-project/.bob/skills/project-context/SKILL.md"
root="$(new_fixture)"
mkdir -p "$root/examples/other"
printf '%s\n' '# Unauthorized example skill' >"$root/examples/other/SKILL.md"
assert_fails \
	'examples/other/SKILL.md: SKILL.md is allowed only under examples/project-review-skills' \
	"$root"

[[ ! -e "$legacy_bob_skill" && ! -L "$legacy_bob_skill" ]] ||
	fail "expected legacy Bob skill source to be absent: $legacy_bob_skill"
assert_contains \
	"Copy \`project-context\` from \`examples/project-review-skills/project-context/\` to \`.bob/skills/project-context/\`." \
	"$bob_instructions"

assert_contains "\`approve\` when no findings remain and no manual checks remain" "$example_skill"
assert_contains "\`needs-attention\` when issues need changes" "$example_skill"
assert_contains "\`needs-manual-check\` when manual checks remain" "$example_skill"
assert_contains "\`not-applicable\` when the target has no user-facing UI" "$example_skill"
assert_contains "Do not use \`approve\` when manual checks remain." "$example_skill"
assert_contains 'policy can be found, stop with an actionable error' "$example_skill"
assert_contains \
	"Any source finding takes precedence over outstanding manual checks: return \`needs-attention\`." \
	"$example_skill"
assert_contains 'Apply only accessibility requirements named by the project policy.' \
	"$example_skill"
assert_contains 'Record the normalized inspected target in every verdict.' "$example_skill"
assert_contains 'Record the normalized inspected target in every target-resolution error.' \
	"$example_skill"
assert_contains 'Use the same base branch or explicit file list as the preceding branch review.' \
	"$example_skill"
assert_contains \
	"Keep outstanding manual checks in the report when source findings return \`needs-attention\`." \
	"$example_skill"

output="$(cd "$repo_root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (35 canonical skills, 2 project review examples)' ]] || fail "$output"

root="$(new_fixture)"
mkdir -p "$root/content/skills/skill-01/scripts"
printf '#!/usr/bin/env bash\n' >"$root/content/skills/skill-01/scripts/run.sh"
chmod 755 "$root/content/skills/skill-01/scripts/run.sh"
(cd "$root" && bash scripts/check-skill-layout.sh >/dev/null)
[[ -x "$root/content/skills/skill-01/scripts/run.sh" ]] || fail 'guard changed file mode'

root="$(new_fixture)"
write_skill "$root" 'content/skills' 'skill-02'
output="$(cd "$root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (2 canonical skills, 1 project review examples)' ]] || fail "$output"

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

assert_package_case() {
	local kind="$1"
	local inventory="$2"
	local name="$3"
	local root target expected matching_count

	root="$(new_fixture)"
	target="$root/$inventory/$name"
	case "$kind" in
	malformed-frontmatter)
		printf '%s\n' '---' "name: $name" 'summary: wrong' '---' '# Body' \
			>"$target/SKILL.md"
		expected="$inventory/$name/SKILL.md: description must be a one-line JSON string"
		;;
	name-mismatch)
		printf '%s\n' '---' 'name: wrong' 'description: "Test skill."' '---' '# Body' \
			>"$target/SKILL.md"
		expected="$inventory/$name/SKILL.md: name must match its skill directory"
		;;
	empty-description)
		printf '%s\n' '---' "name: $name" 'description: ""' '---' '# Body' \
			>"$target/SKILL.md"
		expected="$inventory/$name/SKILL.md: description must contain 1-1024 Unicode scalars"
		;;
	empty-body)
		printf '%s\n' '---' "name: $name" 'description: "Test skill."' '---' \
			>"$target/SKILL.md"
		expected="$inventory/$name/SKILL.md: non-empty Markdown must follow frontmatter"
		;;
	reserved-name)
		mv "$target" "$root/$inventory/plan"
		write_skill "$root" "$inventory" 'plan'
		expected="$inventory/plan: reserved skill name"
		;;
	internal-symlink)
		ln -s SKILL.md "$target/link.md"
		expected="$inventory/$name/link.md: symlinks are forbidden"
		;;
	non-regular-entry)
		mkfifo "$target/runtime"
		expected="$inventory/$name/runtime: only regular files and directories are allowed"
		;;
	non-portable-path)
		printf '%s\n' 'resource' >"$target/café.md"
		expected="$inventory/$name/café.md: path component is not portable ASCII"
		;;
	case-fold-collision)
		printf '%s\n' 'one' >"$target/Readme.md"
		printf '%s\n' 'two' >"$target/readme.md"
		matching_count="$(find "$target" -maxdepth 1 -iname 'readme.md' | wc -l | tr -d ' ')"
		[[ "$matching_count" -eq 2 ]] || return 0
		expected="$inventory: ASCII case-fold path collision"
		;;
	invalid-utf8)
		printf '\377' >"$target/SKILL.md"
		expected="$inventory/$name/SKILL.md: file must be valid UTF-8"
		;;
	*) fail "unknown package case: $kind" ;;
	esac
	assert_fails "$expected" "$root"
}

for inventory_name in 'content/skills:skill-01' \
	'examples/project-review-skills:accessibility-reviewer'; do
	inventory="${inventory_name%%:*}"
	name="${inventory_name#*:}"
	for package_case in malformed-frontmatter name-mismatch empty-description empty-body \
		reserved-name internal-symlink non-regular-entry non-portable-path \
		case-fold-collision invalid-utf8; do
		assert_package_case "$package_case" "$inventory" "$name"
	done
done

root="$(new_fixture)"
printf '%s\n' 'Use ~/.codex/skills here.' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'installed config-root reference is forbidden' "$root"

root="$(new_fixture)"
mv "$root/examples/project-review-skills" "$root/project-review-skills"
assert_fails 'examples/project-review-skills: project review tree is missing' "$root"

root="$(new_fixture)"
printf '%s\n' 'not a package' >"$root/examples/project-review-skills/README.md"
assert_fails 'examples/project-review-skills/README.md: children must be skill directories' "$root"

printf 'check-skill-layout-test: ok (%d focused failures)\n' "$case_count"
