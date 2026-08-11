#!/usr/bin/env bash
set -euo pipefail

# Proves that the POSIX guard in claude-settings-hooks-test.sh is real and wired.
#
# That suite skips its POSIX assertions wherever `sh` is an extended shell, and the verify
# job of .github/workflows/verify.yml sets POSIX_ASSERTIONS_REQUIRED so the skip becomes a
# failure there (ADR 0053). Neither half is exercised by a run on a dash host: the refusal
# branch is never taken, and an unset variable and a correct one produce identical output.
# So both are checked from here, on every host and every CI leg.
#
# Assertions 1 and 2 put a `sh` that is really bash first on PATH. The suite under test
# resolves `sh` through PATH, so that reproduces an image whose /bin/sh is not dash without
# needing such an image. They match the variable name and the verdict string, never the
# prose around them: a green build that depends on the wording of a printf is the coupling
# ADR 0053 rejects.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SUITE="$ROOT/scripts/claude-settings-hooks-test.sh"
WORKFLOW="$ROOT/.github/workflows/verify.yml"
STEP='Prove the hook bodies are POSIX'

fail() {
	printf 'claude-settings-posix-guard-test: %s\n' "$*" >&2
	exit 1
}

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/claude-settings-posix-guard-test.XXXXXX")

cleanup() {
	case $SCRATCH in
	"${TMPDIR:-/tmp}"/claude-settings-posix-guard-test.*) rm -R "$SCRATCH" ;;
	*) printf 'claude-settings-posix-guard-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

ln -s "$(command -v bash)" "$SCRATCH/sh"

# 1. Required, under an extended sh: the suite must refuse rather than skip, and say which
#    variable is doing the refusing.
status=0
output=$(PATH="$SCRATCH:$PATH" POSIX_ASSERTIONS_REQUIRED=1 "$SUITE" 2>&1) || status=$?
[[ $status != 0 ]] ||
	fail 'the suite passed under an extended sh with POSIX_ASSERTIONS_REQUIRED=1: the guard is inert'
[[ $output == *POSIX_ASSERTIONS_REQUIRED* ]] ||
	fail "the refusal does not name POSIX_ASSERTIONS_REQUIRED: $output"

# 2. Not required, same shell: #112's skip is unchanged. Passed as explicitly empty rather
#    than left to the caller's environment, so an operator running the whole suite set does
#    not invert this assertion.
status=0
output=$(PATH="$SCRATCH:$PATH" POSIX_ASSERTIONS_REQUIRED='' "$SUITE" 2>&1) || status=$?
[[ $status == 0 ]] ||
	fail "the suite must still skip when the assertions are not required, got exit $status: $output"
[[ $output == *'POSIX assertions SKIPPED'* ]] ||
	fail "the skip verdict is missing from an unrequired run: $output"

# 3. The wiring is present. Read at step granularity rather than as a match over the file:
#    the same key on another step, the same text in a comment, a deleted `run:` under a
#    surviving `env:`, and a step neutralised with continue-on-error all pass a bare grep.
#    There is no YAML parser in this repository's toolchain, so the step's block is the lines
#    from its `- name:` to the next list item at that indent, comments dropped.
[[ -f $WORKFLOW ]] || fail "no workflow at $WORKFLOW"
block=$(awk -v step="- name: $STEP" '
	function indent(s,   i) { i = match(s, /[^ ]/); return i == 0 ? -1 : i - 1 }
	!found {
		if (substr($0, indent($0) + 1) == step) { base = indent($0); found = 1 }
		next
	}
	{
		if ($0 ~ /^[ \t]*#/) next
		if (indent($0) >= 0 && indent($0) <= base) exit
		print
	}
' "$WORKFLOW")
[[ -n $block ]] ||
	fail "$WORKFLOW has no '$STEP' step: the required check no longer proves the hook bodies"
[[ $block == *'./scripts/claude-settings-hooks-test.sh'* ]] ||
	fail "the '$STEP' step does not run the hooks suite"
printf '%s\n' "$block" |
	grep -qE "^ +POSIX_ASSERTIONS_REQUIRED: *'?1'? *$" ||
	fail "the '$STEP' step does not set POSIX_ASSERTIONS_REQUIRED to 1: the guard is inert"
if printf '%s\n' "$block" | grep -q 'continue-on-error'; then
	fail "the '$STEP' step carries continue-on-error: the gate cannot fail the check"
fi

printf 'claude-settings-posix-guard-test: ok (guard refuses, skip intact, wiring present)\n'
