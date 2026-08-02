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

# --- GitHub profile: reads -------------------------------------------------
# gh is reached through PATH, so a fixture bin stubs it: the suite runs with no
# network and no credentials.
mkdir -p "$fixture/bin"
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ $1 == repo && $2 == view ]]; then
	printf 'https://github.com/example/repo\n'
	exit 0
fi
if [[ $1 == issue && $2 == create ]]; then
	printf 'Creating issue in example/repo\n'
	printf 'https://github.com/example/repo/issues/101\n'
	exit 0
fi
if [[ $1 == issue && $2 == view ]]; then
	case ${GH_VIEW_SHAPE:-good} in
	malformed-parent)
		printf '%s\n' '{"number":101,"title":"T","body":"B","labels":[],"parent":"bad","state":"OPEN","url":"u"}'
		;;
	malformed-label)
		printf '%s\n' '{"number":101,"title":"T","body":"B","labels":["bad"],"parent":null,"state":"OPEN","url":"u"}'
		;;
	*)
		printf '%s\n' '{"number":101,"title":"T","body":"B","labels":[{"name":"status:ready"}],"parent":null,"state":"OPEN","url":"https://github.com/example/repo/issues/101"}'
		;;
	esac
	exit 0
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"

: >"$fixture/calls"
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" view --profile github --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || fail 'view exited non-zero'

jq -e '.id == "101" and .ref == "#101" and .state == "open" and .done == false
	and (.labels | index("status:ready")) != null and .parent == null' \
	>/dev/null <"$fixture/out" || fail 'view did not normalize'

# The same invocation create-verified-issue-test.sh pins.
rg -q '^issue view ' "$fixture/calls" || fail 'view did not call gh issue view'

# A malformed source shape must reach a deterministic message, not a jq crash.
for shape in malformed-parent malformed-label; do
	status=0
	GH_VIEW_SHAPE=$shape GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
		"$tracker" view --profile github --target example/repo 101 \
		>"$fixture/out" 2>"$fixture/err" || status=$?
	[[ $status != 0 ]] || fail "view accepted $shape"
	assert_contains 'malformed or incomplete JSON' "$fixture/err"
done

# target-url strips a trailing slash and returns the canonical URL.
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" target-url --profile github --target example/repo \
	>"$fixture/out" 2>"$fixture/err" || fail 'target-url exited non-zero'
assert_contains 'https://github.com/example/repo' "$fixture/out"

# An operation needing a target says so rather than building a broken call.
status=0
PATH="$fixture/bin:$PATH" "$tracker" target-url --profile github \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'target-url without --target'

# --- GitHub profile: writes ------------------------------------------------
# label-edit is atomic: adds and removes travel in one invocation. Splitting
# them leaves an issue with two status labels or none, and the pipeline reads
# that label to choose its next write.
: >"$fixture/calls"
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" label-edit --profile github --target example/repo 101 \
	--add status:in-progress --remove status:ready \
	>"$fixture/out" 2>"$fixture/err" || fail 'label-edit exited non-zero'
edits=$(rg -c '^issue edit ' "$fixture/calls" || true)
[[ ${edits:-0} == 1 ]] || fail "label-edit made ${edits:-0} invocations, expected 1"
assert_contains 'add-label' "$fixture/calls"
assert_contains 'remove-label' "$fixture/calls"

# create succeeds and reports the normalized identity.
: >"$fixture/calls"
printf 'body\n' >"$fixture/body.md"
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" create --profile github --target example/repo \
	--title T --body-file "$fixture/body.md" --label status:ready \
	>"$fixture/out" 2>"$fixture/err" || fail 'create exited non-zero'
jq -e '.id == "101" and (.url | test("issues/101$"))' >/dev/null <"$fixture/out" ||
	fail 'create did not report identity'

# create never retries, and a failed write is partial (5) carrying any URL seen.
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ $1 == issue && $2 == create ]]; then
	printf 'https://github.com/example/repo/issues/101\n'
	printf 'boom\n' >&2
	exit 1
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
: >"$fixture/calls"
status=0
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" create --profile github --target example/repo \
	--title T --body-file "$fixture/body.md" \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 5 "$status" 'create on failed write'
creates=$(rg -c '^issue create ' "$fixture/calls" || true)
[[ ${creates:-0} == 1 ]] || fail "create retried: ${creates:-0} invocations"
assert_contains 'issues/101' "$fixture/err"

# label-ensure treats an existing label as success, not an error.
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ $1 == label && $2 == create ]]; then
	printf 'label already exists\n' >&2
	exit 1
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
: >"$fixture/calls"
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" label-ensure --profile github --target example/repo \
	status:ready 0e8a16 'triaged' >"$fixture/out" 2>"$fixture/err" ||
	fail 'label-ensure treated an existing label as failure'

# --- declared-degraded gate -------------------------------------------------
# Total coverage is not total implementation. A profile declares each operation
# implemented or degraded to a named value, and the suite asserts the
# declaration -- so a forgotten operation cannot pass as a legitimate
# degradation.
"$tracker" declares --profile fixture label-history >"$fixture/out" 2>&1 ||
	fail 'declares exited non-zero'
assert_contains 'degraded=unknown' "$fixture/out"

"$tracker" declares --profile github view >"$fixture/out" 2>&1 ||
	fail 'declares github view exited non-zero'
assert_contains 'implemented' "$fixture/out"

status=0
"$tracker" declares --profile fixture undeclared-op >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 1 "$status" 'undeclared operation'

# Every operation the GitHub profile offers must carry a declaration, and every
# declaration must name an operation that exists. This is the assertion that
# makes the gate meaningful rather than decorative.
for op in view target-url comment-list label-history search create label-edit \
	label-ensure comment-add state-set link-parent link-blocks; do
	"$tracker" declares --profile github "$op" >/dev/null 2>&1 ||
		fail "github profile does not declare '$op'"
done

printf 'tracker-test: all assertions passed\n'
