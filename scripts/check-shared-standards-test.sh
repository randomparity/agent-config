#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-shared-standards.sh"

if [[ ! -x "$CHECKER" ]]; then
	printf 'checker does not exist: %s\n' "$CHECKER" >&2
	exit 127
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/shared-standards-test.XXXXXX")"
FIXTURE="$SCRATCH/repo"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/shared-standards-test.*) rm -R "$SCRATCH" ;;
	*) printf 'shared-standards-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

BEGIN='<!-- shared-standards:begin -->'
END='<!-- shared-standards:end -->'

CANONICAL='content/instructions/global-development-standards.md'
CLAUDE='agents/claude/shared/CLAUDE.md'
CODEX='agents/codex/shared/AGENTS.md'
BOB='agents/bob/shared/rules/global-development-standards.md'

# The fixture block stands in for the real one. Its wording is irrelevant to
# every assertion here — the gate compares copies and counts subsections, and
# never reads a sentence — so a short synthetic block keeps the suite from
# breaking when the shipped rules are reworded.
canonical_block() {
	printf '%s\n' "$BEGIN"
	printf '## Guardrails\n\n### One\n\nfirst rule\n\n'
	printf '### Two\n\nsecond rule\n\n### Three\n\nthird rule\n'
	printf '%s\n' "$END"
}

drifted_block() {
	canonical_block | sed 's/^second rule$/second rule, reworded/'
}

# Drift a byte no reader would notice, to pin the comparison as byte-exact
# rather than "close enough".
whitespace_block() {
	canonical_block | sed 's/^first rule$/first rule /'
}

# Command substitution strips trailing newlines, so a copy padded with blank
# lines before its end marker compares equal unless the comparison preserves
# them. Byte-identical has to mean byte-identical.
padded_block() {
	printf '%s\n' "$BEGIN"
	printf '## Guardrails\n\n### One\n\nfirst rule\n\n'
	printf '### Two\n\nsecond rule\n\n### Three\n\nthird rule\n\n\n'
	printf '%s\n' "$END"
}

two_subsection_block() {
	printf '%s\n' "$BEGIN"
	printf '## Guardrails\n\n### One\n\nfirst rule\n\n### Two\n\nsecond rule\n'
	printf '%s\n' "$END"
}

duplicated_block() {
	canonical_block
	printf '\n'
	canonical_block
}

# A bad merge that keeps one end marker leaves an unpaired opening, which the
# end-marker count cannot see — and the mirror shape, an unpaired close, which
# the begin-marker count cannot see. Without the second, arithmetic on a
# two-line "line number" fails inside a call whose errexit is suppressed and the
# run reports ok.
duplicated_begin_block() {
	canonical_block | sed "s|^### Two\$|$BEGIN\n\n### Two|"
}

duplicated_end_block() {
	canonical_block | sed "s|^### Two\$|$END\n\n### Two|"
}

unterminated_block() {
	canonical_block | sed "/^$(printf '%s' "$END" | sed 's/[]\/$*.^[]/\\&/g')\$/d"
}

mistyped_begin_block() {
	canonical_block | sed 's/shared-standards:begin/shared-standards:begn/'
}

write_copy() { # relative-path native-prose block-producer
	local relative="$1" native="$2" producer="$3"
	local absolute="$FIXTURE/$relative"

	mkdir -p "$(dirname "$absolute")"
	{
		printf '# Global Development Standards\n\n%s\n\n' "$native"
		"$producer"
	} >"$absolute"
}

reset_fixture() {
	rm -R "$FIXTURE" 2>/dev/null || :
	mkdir -p \
		"$FIXTURE/content/instructions" \
		"$FIXTURE/agents/claude/shared" \
		"$FIXTURE/agents/codex/shared" \
		"$FIXTURE/agents/bob/shared/rules"
	write_copy "$CANONICAL" 'Agent-neutral prose.' canonical_block
	write_copy "$CLAUDE" 'Claude-native prose.' canonical_block
	write_copy "$CODEX" 'Codex-native prose.' canonical_block
	write_copy "$BOB" 'Bob-native prose.' canonical_block
}

run_checker() {
	"$CHECKER" "$FIXTURE" >"$SCRATCH/output" 2>&1
}

assert_passes() { # name
	if ! run_checker; then
		printf 'not ok - %s should pass\n' "$1" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
}

# A location of `path:line` pins the contract's reported position; `path:` on its
# own pins only the file. Asserting the class alone would let a checker report
# any position it liked, which is most of what a reader of the finding needs.
assert_fails() { # name class [location]
	local name="$1" class="$2" location="${3:-}" needle

	if run_checker; then
		printf 'not ok - %s should fail\n' "$name" >&2
		exit 1
	fi
	needle="shared-standards: $class:"
	if [[ -n "$location" ]]; then
		needle="$needle $location"
	fi
	if ! rg -qF -- "$needle" "$SCRATCH/output"; then
		printf 'not ok - %s should report %s\n' "$name" "$needle" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
}

assert_absent() { # name class
	if rg -q "shared-standards: $2:" "$SCRATCH/output"; then
		printf 'not ok - %s should not report %s\n' "$1" "$2" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
}

# The message matters as much as the status: rg exits 2 on its own errors, so a
# checker that had lost its precondition checks entirely would still exit 2 here.
assert_exit_two() { # name expected-message [extra-argument...]
	local name="$1" expected="$2" code=0
	shift 2
	"$CHECKER" "$FIXTURE" "$@" >"$SCRATCH/output" 2>&1 || code=$?
	if ((code != 2)); then
		printf 'not ok - %s should exit 2, exited %s\n' "$name" "$code" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
	if ! rg -qF -- "$expected" "$SCRATCH/output"; then
		printf 'not ok - %s should say %s\n' "$name" "$expected" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
}

reset_fixture
assert_passes 'four identical blocks'

# One case per mirror: a checker that compares only the first copy it finds, or
# only one hardcoded file, passes the other two.
for mirror in "$CLAUDE" "$CODEX" "$BOB"; do
	reset_fixture
	write_copy "$mirror" 'Native prose.' drifted_block
	assert_fails "drift in $mirror" block-drift "$mirror:5"
done

reset_fixture
write_copy "$CLAUDE" 'Claude-native prose.' whitespace_block
assert_fails 'trailing whitespace is drift' block-drift "$CLAUDE:5"

reset_fixture
write_copy "$CLAUDE" 'Claude-native prose.' padded_block
assert_fails 'blank lines before the end marker are drift' block-drift "$CLAUDE:5"

# ripgrep reads RIPGREP_CONFIG_PATH, so a developer's own config would otherwise
# be an input to this gate's verdict. --with-filename turns the line-number field
# into a path, and bash arithmetic on it fails inside a suppressed-errexit call,
# leaving the gate exit 0 having compared nothing. --max-count=1 hides every
# second marker instead. Neither may change the answer.
for directive in --with-filename --max-count=1; do
	reset_fixture
	write_copy "$CODEX" 'Codex-native prose.' drifted_block
	printf -- '%s\n' "$directive" >"$SCRATCH/rgconfig"
	if (
		export RIPGREP_CONFIG_PATH="$SCRATCH/rgconfig"
		"$CHECKER" "$FIXTURE"
	) >"$SCRATCH/output" 2>&1; then
		printf 'not ok - a ripgrep config of %s must not hide drift\n' "$directive" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
	if ! rg -qF -- "shared-standards: block-drift: $CODEX:5" "$SCRATCH/output"; then
		printf 'not ok - %s should leave block-drift reported\n' "$directive" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
done

reset_fixture
printf '# Global Development Standards\n\nClaude-native prose.\n' >"$FIXTURE/$CLAUDE"
assert_fails 'a mirror lost its block' missing-block

# The scan alone cannot see this file any more, which is what the expected-site
# manifest exists for: the body is still there, so nothing else would notice.
reset_fixture
write_copy "$CLAUDE" 'Claude-native prose.' mistyped_begin_block
assert_fails 'a mirror mistyped its begin marker' missing-block

# The canonical block is the comparison source, so a run without one reports
# that alone. Three drift findings against an empty string would bury it.
reset_fixture
printf '# Global Development Standards\n\nAgent-neutral prose.\n' >"$FIXTURE/$CANONICAL"
assert_fails 'the canonical file lost its block' missing-block
assert_absent 'the canonical file lost its block' block-drift

reset_fixture
write_copy "$CODEX" 'Codex-native prose.' duplicated_block
assert_fails 'a second block in one file' duplicate-block "$CODEX:21"

reset_fixture
write_copy "$CODEX" 'Codex-native prose.' duplicated_begin_block
assert_fails 'a second begin marker sharing one end marker' duplicate-block "$CODEX:12"

reset_fixture
write_copy "$CODEX" 'Codex-native prose.' duplicated_end_block
assert_fails 'a second end marker sharing one begin marker' duplicate-block "$CODEX:21"

reset_fixture
write_copy "$BOB" 'Bob-native prose.' unterminated_block
assert_fails 'a block with no end marker' unterminated-block "$BOB:5"

reset_fixture
write_copy "$CANONICAL" 'Agent-neutral prose.' two_subsection_block
write_copy "$CLAUDE" 'Claude-native prose.' two_subsection_block
write_copy "$CODEX" 'Codex-native prose.' two_subsection_block
write_copy "$BOB" 'Bob-native prose.' two_subsection_block
assert_fails 'a canonical block below three subsections' canonical-shape

# The divergence the gate exists to permit. Without this the gate could be
# tightened to whole-file identity and the suite would stay green.
reset_fixture
write_copy "$CLAUDE" 'Read the reference at the Claude config path.' canonical_block
write_copy "$CODEX" 'Read the reference at the Codex config path.' canonical_block
assert_passes 'agent-native prose outside the block may differ'

# Found by the scan, not by the manifest: a stale copy pasted into a file the
# manifest never names is still deployed prose claiming to be these rules.
reset_fixture
write_copy 'agents/codex/shared/notes.md' 'Codex notes.' drifted_block
assert_fails 'a drifted block in an unlisted deployed file' block-drift \
	'agents/codex/shared/notes.md:5'

# The installer copies these trees wholesale, so an ignore entry beside a
# deployed file removes it from the scan while the installer still ships it.
reset_fixture
write_copy 'agents/codex/shared/notes.md' 'Codex notes.' drifted_block
printf 'notes.md\n' >"$FIXTURE/agents/codex/shared/.ignore"
assert_fails 'an ignore file may not hide a deployed carrier' block-drift \
	'agents/codex/shared/notes.md:5'

reset_fixture
rm -R "$FIXTURE/agents/bob/shared"
assert_exit_two 'a missing scan root' 'scan root is missing: agents/bob/shared'

reset_fixture
rm "$FIXTURE/$CANONICAL"
assert_exit_two 'a missing canonical file' "canonical file is missing: $CANONICAL"

reset_fixture
assert_exit_two 'a second argument' 'usage:' extra

printf 'shared-standards-test: ok\n'
