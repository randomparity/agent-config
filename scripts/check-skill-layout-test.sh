#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'check-skill-layout-test: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local expected="$1"
	local file="$2"

	rg --no-config -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
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
	printf '%s\n' "$output" | rg --no-config -Fq "$expected" ||
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
	rg --no-config -N -m1 '^[a-z]{2}_[A-Z]{2}\.(utf8|UTF-8)$' || true)"

example_skill="$repo_root/examples/project-review-skills/accessibility-reviewer/SKILL.md"
bob_instructions="$repo_root/examples/bob-project/AGENTS.md"
repo_instructions="$repo_root/AGENTS.md"
legacy_bob_skill="$repo_root/examples/bob-project/.bob/skills/project-context/SKILL.md"
applicability_line="$(rg --no-config -n '^## Applicability$' "$example_skill" | cut -d: -f1)"
policy_line="$(rg --no-config -n '^## Required project policy$' "$example_skill" | cut -d: -f1)"
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
[[ "$output" == 'skills-check: ok (36 canonical skills, 2 project review examples)' ]] || fail "$output"

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

assert_invalid_utf8() { # label bytes
	local label="$1"
	local bytes="$2"
	local root

	root="$(new_fixture)"
	printf 'malformed %s: %b\n' "$label" "$bytes" \
		>>"$root/content/skills/skill-01/SKILL.md"
	assert_fails 'content/skills/skill-01/SKILL.md: file must be valid UTF-8' "$root"
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

# The `invalid-utf8` package case above is one byte the grammar rejects. These are
# the classes a hand-written acceptor gets wrong: admit any of them and the gate is
# weaker than the `iconv` call it replaced (issue #101). Written as octal escapes
# because the rule is about bytes -- a surrogate or an overlong encoding has no
# character to write literally. Each goes in the body of an otherwise-valid skill,
# so the case fails on the UTF-8 rule rather than on frontmatter it also broke.
assert_invalid_utf8 'lone continuation byte' '\0200'
assert_invalid_utf8 'unexpected continuation after ASCII' 'a\0277'
assert_invalid_utf8 'truncated two-byte sequence' '\0303'
assert_invalid_utf8 'truncated three-byte sequence' '\0342\0200'
assert_invalid_utf8 'truncated four-byte sequence' '\0360\0237\0232'
assert_invalid_utf8 'bad continuation byte' '\0342\0200\0101'
assert_invalid_utf8 'overlong two-byte solidus' '\0300\0257'
assert_invalid_utf8 'overlong two-byte lead' '\0301\0277'
assert_invalid_utf8 'overlong three-byte solidus' '\0340\0200\0257'
assert_invalid_utf8 'overlong four-byte solidus' '\0360\0200\0200\0257'
assert_invalid_utf8 'lone high surrogate U+D800' '\0355\0240\0200'
assert_invalid_utf8 'lone low surrogate U+DFFF' '\0355\0277\0277'
assert_invalid_utf8 'first scalar above U+10FFFF' '\0364\0220\0200\0200'
assert_invalid_utf8 'lead byte outside the grammar' '\0365\0200\0200\0200'
assert_invalid_utf8 'byte that never appears in UTF-8' '\0376\0377'

# Naming the file was what the replaced call did, and issue #101 is what it costs when
# the name is all you get. The line number is the half a reader can act on, so it is
# asserted exactly rather than by substring: `write_skill` lays down five lines.
#
# Pinned under a territory UTF-8 locale, because that is the only place the rule bites:
# the line being trimmed is by definition not decodable there, so an unpinned `.*`
# stops at the first bad byte and drags it into the message. Under the C locale the
# bug is invisible, exactly as with the ASCII-portability cases below.
root="$(new_fixture)"
printf '%b\n' 'a clean line' >>"$root/content/skills/skill-01/SKILL.md"
printf '%b\n' 'and a \0377 byte' >>"$root/content/skills/skill-01/SKILL.md"
assert_fails \
	'content/skills/skill-01/SKILL.md: file must be valid UTF-8 (first malformed line 7)' \
	"$root" "$utf8_locale"

# rg's binary detection triggers on a single NUL byte. For a file named explicitly on
# the command line it converts rather than quits, so the verdict survives -- but the
# reported position does not, and the position is the half of the message worth having.
# Asserting the whole string is what makes --text bite here; a substring assertion let
# the flag be deleted with the suite green.
root="$(new_fixture)"
{
	printf '%b\n' '---\nname: skill-01\ndescription: "Test skill."\n---'
	printf '%b\n' '# Body\0000 then \0377 after the NUL'
} >"$root/content/skills/skill-01/SKILL.md"
assert_fails \
	'content/skills/skill-01/SKILL.md: file must be valid UTF-8 (first malformed line 5)' \
	"$root"

# rg transcodes a UTF-16 file on sight of its BOM, and the transcoded text is
# well-formed by construction -- so without BOM sniffing turned off the validator
# reads UTF-16 as valid UTF-8. Whole-file, because a BOM only counts at offset 0.
root="$(new_fixture)"
printf '%b' '\0377\0376h\0000e\0000l\0000l\0000o\0000' \
	>"$root/content/skills/skill-01/SKILL.md"
assert_fails 'content/skills/skill-01/SKILL.md: file must be valid UTF-8' "$root"

# The case the replaced gate could not hold green: Apple's iconv CLI rejected a
# valid UTF-8 skill file by position rather than by content, and the workaround was
# to strip that file back to ASCII (issue #101, PR #99). Every well-formed width
# has to pass -- including the 4-byte sequences no skill file carries yet, and the
# two scalars at the edges of the grammar.
#
# Every alternative in the acceptor appears here, not just the ones live content uses.
# The reject cases below pin each narrow lead range from one side only: they prove the
# grammar refuses what sits outside it, and would keep passing if an alternative were
# deleted outright. The last line is the other side -- U+0800 and U+D7FF bracket the
# surrogate hole, U+E000 reopens after it, and U+10000 and U+40000 cover the two
# four-byte alternatives the earlier lines miss.
utf8_root="$(new_fixture)"
{
	printf '%b\n' 'caf\0303\0251 \0342\0200\0224 dash \0342\0206\0222 arrow'
	printf '%b\n' 'CJK \0344\0270\0255\0346\0226\0207 emoji \0360\0237\0232\0200'
	printf '%b\n' 'first \0302\0200 last \0364\0217\0277\0277'
	printf '%b\n' 'floor \0340\0240\0200 pre \0355\0237\0277 post \0356\0200\0200'
	printf '%b\n' 'plane1 \0360\0220\0200\0200 plane3 \0361\0200\0200\0200'
} >>"$utf8_root/content/skills/skill-01/SKILL.md"
output="$(cd "$utf8_root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] ||
	fail "valid multi-byte UTF-8 must pass: $output"

# rg applies RIPGREP_CONFIG_PATH before the arguments it is given, so a developer's
# personal config decides what the UTF-8 pattern means: under `--fixed-strings` the
# grammar becomes a literal that matches no line, every line reads as malformed, and
# the gate rejects skill files that are fine -- and the config-root patterns become
# literals that match nothing, so a real violation reports clean. Both directions are
# pinned: a flag that only holds one of them would not be worth carrying.
#
# One option per run, not both in one file. `--fixed-strings` reaches the three calls
# that pass a regex; `--invert-match` reaches the reserved-name check, which already
# passes -F and so cannot notice that one. Together they cancel on the Markdown-body
# check -- inverted, every line lacks the literal `[^[:space:]]`, so the rule answers
# correctly by accident and the flag can be deleted from it with the suite still green.
rg_config="$tmpdir/ripgreprc"
for rg_option in '--fixed-strings' '--invert-match'; do
	printf '%s\n' "$rg_option" >"$rg_config"
	export RIPGREP_CONFIG_PATH="$rg_config"
	output="$(cd "$utf8_root" && bash scripts/check-skill-layout.sh)"
	[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] ||
		fail "rg config $rg_option must not fail a clean tree: $output"
	case_count=$((case_count + 1))
	root="$(new_fixture)"
	printf '%s\n' 'Use ~/.codex/skills here.' >>"$root/content/skills/skill-01/SKILL.md"
	assert_fails 'installed config-root reference is forbidden' "$root"
	unset RIPGREP_CONFIG_PATH
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

# The deployed payload's encoding contract (ADR 0050). Every file the scan walks is
# proven UTF-8 text before either pattern rule reads it, so the two fixtures below --
# a NUL byte and a UTF-16 BOM, the pair issue #101 added `--text` and `--encoding none`
# for -- now stop at the encoding rule instead of reaching the config-root rule. That is
# the point of the contract: neither file is a legitimate delivery, and rejecting it for
# what it is beats guessing how to read it.
#
# The flags those cases pin are unchanged and still pinned here, because
# `run_content_scan` carries one flag list for all four rules. Drop `--text` and the NUL
# pattern becomes impossible to match -- rg exits 2, `run_content_scan` reports a failed
# scan, and the clean-tree assertions above go red. Drop `--encoding none` and the BOM
# file is transcoded into well-formed UTF-8 with its NULs consumed, so both encoding
# rules clear it and this case goes red. Each fixture keeps a forbidden reference in its
# body so that reverting the encoding rule alone leaves the case failing on the
# config-root message rather than passing.
payload_utf8_error='file must be valid UTF-8'
payload_text_error='deployed content must be UTF-8 text'

root="$(new_fixture)"
printf '%b' 'lead\0000\nUse ~/.claude/skills here.\n' >"$root/content/languages/binary.md"
assert_fails "content/languages/binary.md: $payload_text_error" "$root"

root="$(new_fixture)"
printf '%b' '\0377\0376Use ~/.claude/skills here.\n' >"$root/content/languages/bom.md"
assert_fails "content/languages/bom.md: $payload_utf8_error" "$root"

# BOM-less UTF-16 is the half the UTF-8 grammar cannot reach on its own: UTF-16LE text
# drawn from ASCII is a run of `[\x00-\x7F]` bytes, so it satisfies the acceptor exactly
# as written, and rg never transcoded it either -- `--encoding auto` sniffs a BOM and
# this file has none. It is unscannable rather than misread, which is what the NUL rule
# is for. The body is a forbidden reference no pattern rule can see through the
# interleaved NULs.
root="$(new_fixture)"
printf '%b' 'U\0000s\0000e\0000 \0000~\0000.\0000c\0000l\0000a\0000u\0000d\0000e\0000\n' \
	>"$root/content/references/utf16le.md"
assert_fails "content/references/utf16le.md: $payload_text_error" "$root"

# The contract covers every root the config-root scan walks, not just the two that
# deploy verbatim: the non-SKILL.md payload under `content/skills` installs too, and had
# no encoding rule at all before this (issue #127). One case per root, because the scan
# reaches `content/skills` through a separate rg call with its own globs.
for payload_path in \
	'content/skills/skill-01/reference.md' \
	'content/languages/rust.md' \
	'content/references/orchestration.md'; do
	root="$(new_fixture)"
	printf '%b\n' 'a clean line' >"$root/$payload_path"
	printf '%b\n' 'and a \0377 byte' >>"$root/$payload_path"
	assert_fails "$payload_path: $payload_utf8_error (first malformed line 2)" "$root"
done

# The other direction, and the one that matters most in a repository whose content is
# prose: well-formed multi-byte UTF-8 in the payload has to pass. Every alternative in
# the acceptor is already pinned for SKILL.md; this pins that the payload rule uses the
# same acceptor rather than a stricter reading of its own.
root="$(new_fixture)"
{
	printf '%b\n' 'caf\0303\0251 \0342\0200\0224 dash \0342\0206\0222 arrow'
	printf '%b\n' 'CJK \0344\0270\0255\0346\0226\0207 emoji \0360\0237\0232\0200'
	printf '%b\n' 'floor \0340\0240\0200 pre \0355\0237\0277 post \0356\0200\0200'
} >"$root/content/languages/unicode.md"
printf '%b\n' 'plane1 \0360\0220\0200\0200 last \0364\0217\0277\0277' \
	>"$root/content/skills/skill-01/reference.md"
output="$(cd "$root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] ||
	fail "valid multi-byte UTF-8 in the payload must pass: $output"

# The encoding rule honours the `testdata` exclusion the config-root rules already apply
# (ADR 0025), and honours its scoping too: `content/skills` is the one root the installer
# filters, so a `testdata` entry under `content/languages` really does ship and is held to
# the contract. Both halves, because a rule that excluded the name everywhere would blind
# the gate over a deployed path.
root="$(new_fixture)"
mkdir -p "$root/content/skills/skill-01/testdata"
printf '%b\n' 'malformed \0377 fixture' >"$root/content/skills/skill-01/testdata/bad.md"
printf '%b' 'utf16\0000 fixture\n' >"$root/content/skills/skill-01/testdata/utf16.md"
output="$(cd "$root" && bash scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] ||
	fail "testdata must stay excluded from the encoding rule: $output"

root="$(new_fixture)"
mkdir -p "$root/content/languages/testdata"
printf '%b\n' 'malformed \0377 fixture' >"$root/content/languages/testdata/bad.md"
assert_fails "content/languages/testdata/bad.md: $payload_utf8_error" "$root"

# `--hidden` and `--no-ignore` decide *which* files the contract covers, and the contract
# is only as wide as the traversal that carries it. Both were pinned by nothing: the live
# tree has no dot-prefixed or ignored file under the three roots, so a fixture is the only
# place the property exists -- the same argument the `testdata` case above makes for
# itself. `install_managed_path` copies both roots with `cp -pR`, so a dot-prefixed or
# gitignored file really is delivered, and dropping either flag would reopen the
# scanned-narrower-than-delivered hole silently, over the encoding rules as well as the
# pattern ones. rg reads `.ignore` outside a git repository, so the second fixture needs
# no git state.
root="$(new_fixture)"
printf '%b\n' 'malformed \0377 dotfile' >"$root/content/languages/.notes.md"
assert_fails "content/languages/.notes.md: $payload_utf8_error" "$root"

root="$(new_fixture)"
printf '%s\n' 'ignored.md' >"$root/.ignore"
printf '%b\n' 'malformed \0377 ignored file' >"$root/content/references/ignored.md"
assert_fails "content/references/ignored.md: $payload_utf8_error" "$root"

# The reachable case, and the reason the NUL message names a remedy: Finder writes
# `.DS_Store` into any directory a developer opens, `content/languages` and
# `content/references` are the two roots no path rule covers, and the file is gitignored
# so `git status` stays clean. `content/skills` already rejected it on the portable-ASCII
# path rule. macOS is a CI leg and the bash floor, so this is normal use rather than a
# hypothetical.
root="$(new_fixture)"
printf '%b' 'Bud1\0000\0000\0000\0000\0000' >"$root/content/references/.DS_Store"
assert_fails \
	"content/references/.DS_Store: $payload_text_error (file contains a NUL byte); delete it or move it out of the delivered tree" \
	"$root"

# rg exits 2 for any scan it could not complete, and the gate used to read that
# as "no matches" and report ok. Root reads an unreadable file, so there the case
# would assert nothing. The UTF-8 rule has the same three-way exit and the same
# failure mode, so both branches are pinned rather than only the older one.
if [[ "$EUID" -ne 0 ]]; then
	root="$(new_fixture)"
	printf '%s\n' 'Use ~/.claude/skills here.' >"$root/content/languages/unreadable.md"
	chmod 000 "$root/content/languages/unreadable.md"
	assert_fails 'content scan failed' "$root"
	chmod 644 "$root/content/languages/unreadable.md"

	root="$(new_fixture)"
	chmod 000 "$root/content/skills/skill-01/SKILL.md"
	assert_fails 'content/skills/skill-01/SKILL.md: UTF-8 scan failed' "$root"
	chmod 644 "$root/content/skills/skill-01/SKILL.md"
fi

# Every command the gate runs apart from rg. `iconv` is deliberately absent: the
# UTF-8 rule stopped shelling out to it in issue #101, and the case below is what
# stops it coming back -- a PATH holding exactly the declared prerequisites has to
# validate multi-byte content, not fail closed on a tool nobody installs.
shim_tools=(dirname mktemp find sed jq wc tr sort cut uniq rm)

utf8_shim="$tmpdir/utf8-shim-bin"
mkdir -p "$utf8_shim"
for shim_tool in "${shim_tools[@]}" rg; do
	ln -s "$(command -v "$shim_tool")" "$utf8_shim/$shim_tool"
done
output="$(cd "$utf8_root" && PATH="$utf8_shim" "$BASH" scripts/check-skill-layout.sh)"
[[ "$output" == 'skills-check: ok (1 canonical skills, 1 project review examples)' ]] ||
	fail "gate must validate UTF-8 with only its declared prerequisites: $output"
case_count=$((case_count + 1))

# The sink proof has to hold from inside a command substitution, which is where
# `validate_utf8` actually runs: bash does not carry set -e into `count="$(...)"`, so a
# bare `: >` failed, execution continued, rg never ran, and its unrun 1 is the same 1
# that means "every line is well-formed" -- the gate reported 36 valid skill files
# having read no bytes. `shopt -s inherit_errexit` is not the fix to lean on: bash 3.2
# is the macOS system shell this repo targets and does not have it.
#
# A mktemp shim is what reaches the failure without root or a full filesystem. It hands
# back the workspace the gate asked for, with one sink path already occupied by a
# directory, and leaves every other path alone -- so the case fails on the sink proof
# rather than on a workspace that was never usable.
sabotage_bin="$tmpdir/sabotage-bin"
mkdir -p "$sabotage_bin"
cat >"$sabotage_bin/mktemp" <<EOF
#!/usr/bin/env bash
real='$(command -v mktemp)'
EOF
cat >>"$sabotage_bin/mktemp" <<'EOF'
set -euo pipefail
target="$("$real" "$@")"
mkdir "$target/utf8-bad"
printf '%s\n' "$target"
EOF
chmod 755 "$sabotage_bin/mktemp"
root="$(new_fixture)"
set +e
output="$(cd "$root" && PATH="$sabotage_bin:$PATH" bash scripts/check-skill-layout.sh 2>&1)"
status="$?"
set -e
[[ "$status" -ne 0 ]] ||
	fail "expected failure when a UTF-8 scan sink cannot be created; got: $output"
printf '%s\n' "$output" | rg --no-config -Fq 'UTF-8 scan failed: cannot create' ||
	fail "expected the sink proof to fire; got: $output"
case_count=$((case_count + 1))

# An absent rg has to be an error too: `if rg -Fxq` reads exit 127 as "not a
# reserved name" and the config-root scan read it as "no matches". The shim
# directory holds every other command the gate runs, so the failure below is the
# rg guard rather than whichever tool PATH happened to drop first.
shim_bin="$tmpdir/shim-bin"
mkdir -p "$shim_bin"
for shim_tool in "${shim_tools[@]}"; do
	ln -s "$(command -v "$shim_tool")" "$shim_bin/$shim_tool"
done
root="$(new_fixture)"
set +e
output="$(cd "$root" && PATH="$shim_bin" "$BASH" scripts/check-skill-layout.sh 2>&1)"
status="$?"
set -e
[[ "$status" -ne 0 ]] || fail 'expected failure when rg is absent'
printf '%s\n' "$output" | rg --no-config -Fq 'skills-check: rg is required' ||
	fail "expected the rg guard to fire; got: $output"
case_count=$((case_count + 1))

root="$(new_fixture)"
mv "$root/examples/project-review-skills" "$root/project-review-skills"
assert_fails 'examples/project-review-skills: project review tree is missing' "$root"

root="$(new_fixture)"
printf '%s\n' 'not a package' >"$root/examples/project-review-skills/README.md"
assert_fails 'examples/project-review-skills/README.md: children must be skill directories' "$root"

printf 'check-skill-layout-test: ok (%d focused failures)\n' "$case_count"
