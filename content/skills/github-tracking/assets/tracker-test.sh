#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tracker="$script_dir/tracker.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/tracker-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

fail() {
	printf 'tracker-test: %s\n' "$*" >&2
	exit 1
}

assert_exit() {
	local expected=$1 actual=$2 label=$3
	[[ $actual == "$expected" ]] ||
		fail "$label: expected exit $expected, got $actual"
}

assert_contains() {
	local needle=$1 file=$2
	rg -F -- "$needle" "$file" >/dev/null || fail "missing '$needle' in $file"
}

# A repo whose AGENTS.md declares nothing resolves to github.
mkdir -p "$fixture/norepo"
status=0
(cd "$fixture/norepo" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 0 "$status" 'resolve with no declaration'
assert_contains 'github' "$fixture/out"

# A malformed declaration is an error, not an absence: silently treating a typo
# as "no declaration" is a wrong-tracker write by another route.
mkdir -p "$fixture/badrepo"
git -C "$fixture/badrepo" init -q
printf 'issue-tracker: NotValid!\n' >"$fixture/badrepo/AGENTS.md"
status=0
(cd "$fixture/badrepo" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 1 "$status" 'resolve with malformed declaration'
assert_contains 'malformed' "$fixture/err"

# More than one declaration is an error rather than first-wins.
mkdir -p "$fixture/duprepo"
git -C "$fixture/duprepo" init -q
printf 'issue-tracker: github\nissue-tracker: github\n' >"$fixture/duprepo/AGENTS.md"
status=0
(cd "$fixture/duprepo" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 1 "$status" 'resolve with duplicate declarations'

# A tracker with no profile is an actionable error at the operation boundary,
# never a silent fallback. Tested with --profile so it needs no profiles on
# disk, and the code path is the same one a declaration reaches.
status=0
"$tracker" view --profile nosuchtracker 1 >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 1 "$status" 'operation with unknown profile'
assert_contains 'nosuchtracker' "$fixture/err"

# An unknown operation is a usage error.
status=0
"$tracker" nosuchop >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'unknown operation'

printf 'tracker-test: all assertions passed\n'
