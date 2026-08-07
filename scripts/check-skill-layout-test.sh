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

assert_fails() { # expected root [locale]
	local expected="$1"
	local root="$2"
	local locale_name="${3:-}"
	local output
	local status

	set +e
	if [[ -n "$locale_name" ]]; then
		output="$(cd "$root" && LC_ALL="$locale_name" LANG="$locale_name" \
			bash scripts/check-skill-layout.sh 2>&1)"
	else
		output="$(cd "$root" && bash scripts/check-skill-layout.sh 2>&1)"
	fi
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
		"$root/agents/codex/shared" "$root/agents/bob/shared" \
		"$root/content/languages" "$root/content/references"
	cp "$implementation" "$root/scripts/check-skill-layout.sh"
	cp "$reserved" "$root/scripts/reserved-skill-names.txt"
	# The two roots `install_common_content` deploys verbatim. The guard fails
	# closed when either is absent, so a fixture without them fails on the
	# missing root rather than on the rule the case targets. Each holds a file:
	# the config-root scan below reads them, and an empty directory would leave
	# it scanning nothing.
	printf '%s\n' '# Fixture language reference.' >"$root/content/languages/bash.md"
	printf '%s\n' '# Fixture shared reference.' >"$root/content/references/style.md"
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
# Widen before removing: a case below leaves a fixture file mode 000 to make rg
# fail its scan, and `rm -R` prompts on a write-protected file when stdin is a
# terminal -- so a case that failed before restoring the mode would hang cleanup.
trap 'chmod -R u+rwX "$tmpdir" 2>/dev/null || true; rm -R "$tmpdir"' EXIT
case_count=0

# The ASCII-portability rules are bracket expressions, and bash takes a bracket
# range from the locale's collation -- so the property worth asserting is that
# they bite under the locale a developer actually runs, not under whichever one
# this suite inherits. Pin a territory UTF-8 locale where the host has one.
# `C.UTF-8` is deliberately not accepted as a substitute: it does not reproduce
# the collation behaviour, so a suite that settled for it would pass while the
# defect was live (ADR 0023). With no such locale installed the cases below still
# run under the inherited locale -- they stop proving the property, rather than
# turning a portability check into a host-configuration check.
utf8_locale="$(locale -a 2>/dev/null |
	rg -N -m1 '^[a-z]{2}_[A-Z]{2}\.(utf8|UTF-8)$' || true)"

example_skill="$repo_root/examples/project-review-skills/accessibility-reviewer/SKILL.md"
bob_instructions="$repo_root/examples/bob-project/AGENTS.md"
repo_instructions="$repo_root/AGENTS.md"
legacy_bob_skill="$repo_root/examples/bob-project/.bob/skills/project-context/SKILL.md"
applicability_line="$(rg -n '^## Applicability$' "$example_skill" | cut -d: -f1)"
policy_line="$(rg -n '^## Required project policy$' "$example_skill" | cut -d: -f1)"
[[ "$applicability_line" -lt "$policy_line" ]] ||
	fail 'accessibility applicability must precede project-policy discovery'
root="$(new_fixture)"
mkdir -p "$root/examples/other"
printf '%s\n' '# Unauthorized example skill' >"$root/examples/other/SKILL.md"
assert_fails \
	'examples/other/SKILL.md: SKILL.md is allowed only under examples/project-review-skills' \
	"$root"

root="$(new_fixture)"
ln -s project-review-skills/accessibility-reviewer "$root/examples/other"
assert_fails 'examples/other: directory symlinks are forbidden' "$root"

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
assert_contains \
	'If the found policy declares no accessibility baseline or requirements, stop before reviewing.' \
	"$example_skill"
assert_contains 'Identify the policy and the owner or action needed to declare requirements.' \
	"$example_skill"
assert_contains "Do not return \`approve\` for a policy with no declared accessibility requirements." \
	"$example_skill"
assert_contains 'Record the normalized inspected target in every verdict.' "$example_skill"
assert_contains 'When target resolution fails, report the raw unresolved input.' \
	"$example_skill"
assert_contains 'Also report the accepted base-branch or explicit-file-list forms.' \
	"$example_skill"
assert_contains 'Create the normalized inspected target only after resolution succeeds.' \
	"$example_skill"
assert_contains \
	'Stop an empty or unresolved target before any review work or verdict.' \
	"$example_skill"
assert_contains 'Use the same base branch or explicit file list as the preceding branch review.' \
	"$example_skill"
assert_contains \
	"Keep outstanding manual checks in the report when source findings return \`needs-attention\`." \
	"$example_skill"
assert_contains \
	'Record the policy requirement and its source location' \
	"$example_skill"
assert_contains 'Keep native settings, instruction files, modes, and MCP files under' \
	"$repo_instructions"

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

# Both rules below are ranges rewritten as explicit ASCII enumerations. Under a
# territory UTF-8 locale the range forms admit accented letters, so these two
# cases are what stops the enumerations from being "simplified" back.
root="$(new_fixture)"
printf '%s\n' 'resource' >"$root/content/skills/skill-01/café.md"
assert_fails 'content/skills/skill-01/café.md: path component is not portable ASCII' \
	"$root" "$utf8_locale"

# The reserved inventory is the one non-ASCII site the path rule cannot reach:
# its entries are read from a file rather than found on disk.
root="$(new_fixture)"
printf '%s\n' 'café' >>"$root/scripts/reserved-skill-names.txt"
assert_fails 'scripts/reserved-skill-names.txt: invalid name: café' "$root" "$utf8_locale"

root="$(new_fixture)"
printf '%s\n' 'Use ~/.codex/skills here.' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'installed config-root reference is forbidden' "$root"

# The config-root scan excludes `testdata` exactly as `stage_skills` does (ADR
# 0025), and no path on the repository tree exercises that exclusion -- a fixture
# is the only place the excluded content exists, so it is the only place the
# exclusion can be shown to work.
root="$(new_fixture)"
mkdir -p "$root/content/skills/skill-01/testdata"
printf '%s\n' 'Use ~/.claude/skills here.' \
	>"$root/content/skills/skill-01/testdata/fixture.md"
output="$(cd "$root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] || fail "$output"

# The exclusion is scoped to `content/skills`, the one root the installer
# filters. `content/languages` deploys verbatim, so a `testdata` entry there
# really does ship and has to stay visible to the scan.
root="$(new_fixture)"
mkdir -p "$root/content/languages/testdata"
printf '%s\n' 'Use ~/.claude/skills here.' >"$root/content/languages/testdata/fixture.md"
assert_fails 'installed config-root reference is forbidden' "$root"

# Repo-relative agent state. The rule above catches `~/.codex/skills`; this one
# catches `.codex/campaigns/x.md`, the shape that put a Codex-named directory into
# every agent's projection. A bare root has to keep passing, so each arm is pinned
# in both directions rather than left to the live tree -- which covers neither
# `.claude` nor `.bob` at all, and so would clear a dropped alternative silently.
repo_state_error='repo-relative agent state path is forbidden'

for state_path in \
	'.codex/campaigns/x.md' \
	'.superpowers/sdd/progress.md' \
	'.claude/settings/x.json' \
	'.bob/skills/x/SKILL.md' \
	'.codex/.gitignore'; do
	root="$(new_fixture)"
	printf 'State goes in %s here.\n' "$state_path" >>"$root/content/skills/skill-01/SKILL.md"
	assert_fails "$repo_state_error" "$root"
done

# The legitimate bare mentions, each terminating a different way. The first four
# are the live forms: three skills name `.codex/` as where a harness's native
# worktree tool nests a worktree, `campaign` notes that target repos track it, and
# `stop-server.sh` closes the root with `)` rather than a backtick. `.codex-plugin`
# is a real Codex path that the slash anchor -- not the terminator set -- excludes.
# shellcheck disable=SC2016 # the backticks are literal Markdown code spans, and the
# byte after the slash is exactly what these fixtures pin -- expanding them would
# delete the terminator under test.
for bare_mention in \
	'Refuse it if it nests under `.codex/`, a project-local dir.' \
	'Persistent directories (.superpowers/) are kept.' \
	'Many target repos track `.codex/` themselves.' \
	"const p = path.join(root, '.codex-plugin/plugin.json')" \
	'State goes in .agent/campaigns/x.md here.'; do
	root="$(new_fixture)"
	printf '%s\n' "$bare_mention" >>"$root/content/skills/skill-01/SKILL.md"
	output="$(cd "$root" && bash scripts/check-skill-layout.sh)"
	[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] ||
		fail "bare mention should pass: $bare_mention: $output"
done

# The repo-relative rule covers every root the home-rooted rule covers. Neither
# `content/languages` nor `content/references` creates state today, and both deploy
# verbatim, so a state path added to either has to be caught the same way.
root="$(new_fixture)"
printf '%s\n' 'State goes in .codex/campaigns/x.md here.' >>"$root/content/languages/python.md"
assert_fails "$repo_state_error" "$root"

# rg exits 2 for any scan it could not complete, and the gate used to read that
# as "no matches" and report ok. Root reads an unreadable file, so there the case
# would assert nothing.
if [[ "$EUID" -ne 0 ]]; then
	root="$(new_fixture)"
	printf '%s\n' 'Use ~/.claude/skills here.' >"$root/content/languages/unreadable.md"
	chmod 000 "$root/content/languages/unreadable.md"
	assert_fails 'config-root scan failed' "$root"
	chmod 644 "$root/content/languages/unreadable.md"
fi

# An absent rg has to be an error too: `if rg -Fxq` reads exit 127 as "not a
# reserved name" and the config-root scan read it as "no matches". The shim
# directory holds every other command the gate runs, so the failure below is the
# rg guard rather than whichever tool PATH happened to drop first.
shim_bin="$tmpdir/shim-bin"
mkdir -p "$shim_bin"
for shim_tool in dirname mktemp find iconv sed jq wc tr sort cut uniq rm; do
	ln -s "$(command -v "$shim_tool")" "$shim_bin/$shim_tool"
done
root="$(new_fixture)"
set +e
output="$(cd "$root" && PATH="$shim_bin" "$BASH" scripts/check-skill-layout.sh 2>&1)"
status="$?"
set -e
[[ "$status" -ne 0 ]] || fail 'expected failure when rg is absent'
printf '%s\n' "$output" | rg -Fq 'skills-check: rg is required' ||
	fail "expected the rg guard to fire; got: $output"
case_count=$((case_count + 1))

root="$(new_fixture)"
mv "$root/examples/project-review-skills" "$root/project-review-skills"
assert_fails 'examples/project-review-skills: project review tree is missing' "$root"

root="$(new_fixture)"
printf '%s\n' 'not a package' >"$root/examples/project-review-skills/README.md"
assert_fails 'examples/project-review-skills/README.md: children must be skill directories' "$root"

printf 'check-skill-layout-test: ok (%d focused failures)\n' "$case_count"
