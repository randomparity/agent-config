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

# Three distinct paths default to github, and each is a place where a
# regression would silently change which tracker a write reaches.
# (a) no git root at all
mkdir -p "$fixture/norepo"
status=0
(cd "$fixture/norepo" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 0 "$status" 'resolve outside a git repo'
assert_contains 'github' "$fixture/out"

# (b) a git root with no AGENTS.md
mkdir -p "$fixture/noagents"
git -C "$fixture/noagents" init -q
status=0
(cd "$fixture/noagents" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 0 "$status" 'resolve with no AGENTS.md'
assert_contains 'github' "$fixture/out"

# (c) an AGENTS.md with content but no issue-tracker line -- must reach the
# default, not the malformed-typo die
mkdir -p "$fixture/noline"
git -C "$fixture/noline" init -q
printf '# Instructions\n\nNothing about trackers here.\n' >"$fixture/noline/AGENTS.md"
status=0
(cd "$fixture/noline" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 0 "$status" 'resolve with AGENTS.md lacking a declaration'
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

# Both directions, derived from the profile rather than a hand-kept list: an
# operation added without a declaration must fail the gate immediately, and a
# declaration naming no function must fail it too.
# Named so they do not themselves match profile_*, which would make each helper
# look like an undeclared operation. Sourcing only binds names, so no stubs for
# die or the exit constants are needed.
list_profile_functions() { # profile-path
	(
		# shellcheck source=/dev/null
		. "$1"
		declare -F | sed -n 's/^declare -f profile_//p'
	)
}
list_profile_declarations() { # profile-path
	(
		# shellcheck source=/dev/null
		. "$1"
		printf '%s\n' "$PROFILE_DECLARES" | sed -n 's/:.*//p'
	)
}

for prof in github fixture; do
	path="$script_dir/profiles/$prof.sh"
	while IFS= read -r fn; do
		[[ -n $fn ]] || continue
		list_profile_declarations "$path" | rg -qx -- "$fn" ||
			fail "$prof defines profile_$fn with no declaration"
	done < <(list_profile_functions "$path")
	while IFS= read -r decl; do
		[[ -n $decl ]] || continue
		list_profile_functions "$path" | rg -qx -- "$decl" ||
			fail "$prof declares '$decl' but defines no profile_$decl"
	done < <(list_profile_declarations "$path")
done

# A degraded operation must actually return its declared value, not merely be
# listed as degraded.
declared=$("$tracker" declares --profile fixture label-history)
[[ $declared == degraded=* ]] || fail 'fixture label-history is not declared degraded'
observed=$("$tracker" label-history --profile fixture 1 label)
[[ $observed == "${declared#degraded=}" ]] ||
	fail "fixture label-history returned '$observed', declared '${declared#degraded=}'"

# --- error payload contract -------------------------------------------------
# Assert exit codes by value and parse the object: a substring match would pass
# on any non-zero exit, which is how a wrong class stays invisible.
assert_error() { # file expected-class label
	local file=$1 class=$2 label=$3
	jq -e --arg c "$class" '.error == $c' >/dev/null <"$file" ||
		fail "$label: error class is not '$class' (payload: $(cat "$file"))"
}

cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
case ${GH_FAIL:-none} in
notfound) printf 'gh: issue not found\n' >&2; exit 1 ;;
auth) printf 'gh: HTTP 401 authentication required\n' >&2; exit 1 ;;
transport) printf 'gh: dial tcp: i/o timeout\n' >&2; exit 1 ;;
esac
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"

status=0
GH_FAIL=notfound GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" view --profile github --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 2 "$status" 'view against a missing issue'
assert_error "$fixture/err" not-found 'not-found'

status=0
GH_FAIL=auth GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" view --profile github --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 3 "$status" 'view with expired auth'
assert_error "$fixture/err" auth 'auth'

status=0
GH_FAIL=transport GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" view --profile github --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 4 "$status" 'view with a transport failure'
assert_error "$fixture/err" transport 'transport'

# A missing positional is a usage error carrying the contract's object, not a
# raw bash unbound-variable abort leaking a local path.
status=0
PATH="$fixture/bin:$PATH" "$tracker" view --profile github --target example/repo \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'view with no issue id'
assert_error "$fixture/err" usage 'missing positional'

# label-edit names what it requested so a caller can repair a half-applied delta.
status=0
GH_FAIL=transport GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" label-edit --profile github --target example/repo 101 \
	--add status:ready >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 5 "$status" 'label-edit on a failed write'
jq -e '.partial.requested_adds | index("status:ready")' >/dev/null <"$fixture/err" ||
	fail 'label-edit partial does not name the requested adds'

# Removing a label the issue does not carry is a success.
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" label-edit --profile github --target example/repo 101 \
	--remove not-present >"$fixture/out" 2>"$fixture/err" ||
	fail 'removing an absent label was treated as failure'

# --- every declared-implemented operation is actually exercised --------------
# A name-symmetry check passes whether the function works, silently no-ops, or
# posts a malformed body. link-parent shipped broken behind exactly that gap.
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ ${GH_FAIL:-none} == notfound ]]; then
	printf 'gh: Not Found (HTTP 404)\n' >&2
	exit 1
fi
if [[ $1 == issue && $2 == view ]]; then
	case " $* " in
	*" comments "*) printf '%s\n' '{"comments":[{"body":"first"},{"body":"second"}]}' ;;
	*" body "*) printf 'existing body\r\nBlocked by #7\r\n' ;;
	*) printf '%s\n' '{"number":101,"title":"T","body":"B","labels":[],"parent":null,"state":"OPEN","url":"u","updatedAt":"2026-01-01T00:00:00Z"}' ;;
	esac
	exit 0
fi
if [[ $1 == api ]]; then
	case " $* " in
	*"/timeline"*) printf '2026-01-02T03:04:05Z\n' ;;
	*"/sub_issues"*) printf '{}\n' ;;
	*) printf '5039780970\n' ;;
	esac
	exit 0
fi
if [[ $1 == search ]]; then
	printf '%s\n' '["101","102"]'
	exit 0
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
run_op() { # label -- args...
	local label=$1
	shift 2
	: >"$fixture/calls"
	GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
		"$tracker" "$@" >"$fixture/out" 2>"$fixture/err" ||
		fail "$label exited non-zero: $(cat "$fixture/err")"
}

run_op comment-list -- comment-list --profile github --target example/repo 101
jq -e 'length == 2 and .[0] == "first"' >/dev/null <"$fixture/out" ||
	fail 'comment-list did not return the comment bodies'

run_op label-history -- label-history --profile github --target example/repo 101 status:ready
assert_contains '2026-01-02T03:04:05Z' "$fixture/out"
rg -q -- '--slurp' "$fixture/calls" ||
	fail 'label-history did not aggregate pages before filtering'

run_op search -- search --profile github --target example/repo --label status:ready \
	--updated-before 2026-01-01
jq -e 'length == 2' >/dev/null <"$fixture/out" || fail 'search did not return ids'
rg -q 'updated:' "$fixture/calls" || fail 'search dropped the updated-before predicate'

run_op comment-add -- comment-add --profile github --target example/repo 101 "$fixture/body.md"
rg -q '^issue comment ' "$fixture/calls" || fail 'comment-add did not comment'

run_op state-set -- state-set --profile github --target example/repo 101 closed
rg -q '^issue close ' "$fixture/calls" || fail 'state-set closed did not close'
run_op state-set-open -- state-set --profile github --target example/repo 101 open
rg -q '^issue reopen ' "$fixture/calls" || fail 'state-set open did not reopen'

# link-parent must send the child's database id, typed -- not its issue number.
run_op link-parent -- link-parent --profile github --target example/repo 43 4
rg -q -- '-F sub_issue_id=5039780970' "$fixture/calls" ||
	fail 'link-parent did not send a typed database id'
rg -q -- 'sub_issue_id=43' "$fixture/calls" &&
	fail 'link-parent sent the issue number instead of the database id'

# link-blocks is idempotent against a CRLF body.
run_op link-blocks -- link-blocks --profile github --target example/repo 7 101
edits=$(rg -c '^issue edit ' "$fixture/calls" || true)
[[ ${edits:-0} == 0 ]] ||
	fail 'link-blocks rewrote a body that already carried the link (CRLF guard)'

# view now carries a real updated timestamp rather than a permanent null.
run_op view-updated -- view --profile github --target example/repo 101
jq -e '.updated == "2026-01-01T00:00:00Z"' >/dev/null <"$fixture/out" ||
	fail 'view did not populate updated'

# gh's real 404 wording classifies as not-found on the REST paths too.
status=0
GH_FAIL=notfound GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" label-history --profile github --target example/repo 101 status:ready \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 2 "$status" 'label-history against a missing repo'
assert_error "$fixture/err" not-found "gh's real 404 wording"

# --- stderr must never become the payload -----------------------------------
# gh prints its release-update notice on stderr while exiting 0. Merging the
# streams made that notice part of the value.
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
printf 'A new release of gh is available: 2.60.0\n' >&2
if [[ $1 == repo && $2 == view ]]; then
	printf 'https://github.com/example/repo\n'
	exit 0
fi
if [[ $1 == issue && $2 == view ]]; then
	printf '%s\n' '{"number":101,"title":"T","body":"B","labels":[],"parent":null,"state":"OPEN","url":"u","updatedAt":"2026-01-01T00:00:00Z"}'
	exit 0
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"

run_op target-url-noise -- target-url --profile github --target example/repo
[[ $(cat "$fixture/out") == 'https://github.com/example/repo' ]] ||
	fail "stderr noise leaked into the payload: $(cat "$fixture/out")"

run_op view-noise -- view --profile github --target example/repo 101
jq -e '.id == "101"' >/dev/null <"$fixture/out" ||
	fail 'stderr noise broke the view payload'

# --- link-blocks actually writes when the link is absent --------------------
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
if [[ $1 == issue && $2 == view ]]; then
	printf 'a body with no link\n'
	exit 0
fi
if [[ $1 == issue && $2 == edit ]]; then
	for arg in "$@"; do
		[[ -f $arg ]] && cp "$arg" "$GH_BODY_COPY"
	done
	exit 0
fi
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
: >"$fixture/calls"
GH_BODY_COPY="$fixture/written-body" GH_CALL_LOG="$fixture/calls" \
	PATH="$fixture/bin:$PATH" \
	"$tracker" link-blocks --profile github --target example/repo 7 101 \
	>"$fixture/out" 2>"$fixture/err" || fail 'link-blocks write path failed'
rg -q '^issue edit ' "$fixture/calls" ||
	fail 'link-blocks did not write when the link was absent'
assert_contains 'Blocked by #7' "$fixture/written-body"
assert_contains 'a body with no link' "$fixture/written-body"

# A non-numeric blocker never reaches the regex it would be spliced into.
status=0
PATH="$fixture/bin:$PATH" "$tracker" link-blocks --profile github \
	--target example/repo 'x)|(' 101 >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'link-blocks with a non-numeric blocker'
assert_error "$fixture/err" usage 'non-numeric blocker'

# --- every operation taking an issue selector calls the guard ---------------
# Derived from the profile rather than a hand-kept list, like the declaration
# gate above: an operation added later that takes an issue selector and forgets
# github_require_id fails here, where a list of today's operations would not.
# The exemptions are the operations whose contract names no issue, so adding one
# is a visible decision rather than a silent omission. Presence, not arity: an
# operation taking two selectors that guards one and forgets the other passes
# here, which is why the per-selector cases below name both of link-parent's.
guard_exempt='^(target_url|label_ensure|search)$'
while IFS= read -r op; do
	[[ -n $op ]] || continue
	[[ $op =~ $guard_exempt ]] && continue
	(
		# shellcheck source=/dev/null
		. "$script_dir/profiles/github.sh"
		declare -f "profile_$op"
	) | rg -q 'github_require_id' ||
		fail "github's profile_$op takes an issue selector but never calls github_require_id"
done < <(list_profile_declarations "$script_dir/profiles/github.sh")

# --- every positional naming an issue is a number ---------------------------
# Callers compose these from issue references read out of GitHub bodies, which
# any account can write, and label-history and link-parent interpolate them into
# a REST path segment. One case per selector the operations take today; the
# derived check above is what covers an operation added later.
assert_rejects_id() { # label -- tracker-args...
	local label=$1 status=0
	shift 2
	: >"$fixture/calls"
	GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
		"$tracker" "$@" >"$fixture/out" 2>"$fixture/err" || status=$?
	assert_exit 1 "$status" "$label with a non-numeric id"
	assert_error "$fixture/err" usage "$label with a non-numeric id"
	[[ ! -s $fixture/calls ]] || fail "$label reached gh with a non-numeric id"
}

assert_rejects_id view -- view --profile github --target example/repo x
assert_rejects_id comment-list -- comment-list --profile github --target example/repo x
assert_rejects_id label-history -- label-history --profile github --target example/repo \
	'1/../../victim/secret/issues/1' status:ready
assert_rejects_id label-edit -- label-edit --profile github --target example/repo x \
	--add status:ready
assert_rejects_id comment-add -- comment-add --profile github --target example/repo x \
	"$fixture/body.md"
assert_rejects_id state-set -- state-set --profile github --target example/repo x closed
assert_rejects_id link-parent-child -- link-parent --profile github --target example/repo \
	'1/../../victim/secret/issues/1' 4
assert_rejects_id link-parent-parent -- link-parent --profile github --target example/repo \
	43 '4/../../victim/secret/issues/4'
assert_rejects_id link-blocks-blocked -- link-blocks --profile github --target example/repo \
	7 x
assert_rejects_id create-parent -- create --profile github --target example/repo \
	--title T --body-file "$fixture/body.md" --parent x

# --- a failure that cannot have written is not partial ----------------------
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
printf '%s\n' "${GH_ERR_TEXT:-boom}" >&2
exit 1
FAKE_GH
chmod +x "$fixture/bin/gh"

# 401: nothing was written, so claiming the issue may exist is worse than
# reporting the failure.
status=0
GH_ERR_TEXT='gh: HTTP 401: Bad credentials' GH_CALL_LOG="$fixture/calls" \
	PATH="$fixture/bin:$PATH" \
	"$tracker" create --profile github --target example/repo --title T \
	--body-file "$fixture/body.md" >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 3 "$status" 'create against bad credentials'
assert_error "$fixture/err" auth 'create auth failure is not partial'

# A transport failure genuinely may have written, so it stays partial.
status=0
GH_ERR_TEXT='dial tcp: i/o timeout' GH_CALL_LOG="$fixture/calls" \
	PATH="$fixture/bin:$PATH" \
	"$tracker" create --profile github --target example/repo --title T \
	--body-file "$fixture/body.md" >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 5 "$status" 'create on a transport failure'
assert_error "$fixture/err" partial 'create transport failure stays partial'

# --- every search predicate is scoped to --target ---------------------------
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
printf '[]\n'
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
for pred in --label --parent --updated-before --text; do
	: >"$fixture/calls"
	GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
		"$tracker" search --profile github --target example/repo \
		"$pred" 'x repo:victim/secret' >/dev/null 2>&1 || true
	rg -q 'repo:victim/secret[^"]*$' "$fixture/calls" &&
		fail "$pred escaped --target scoping"
done

# --- comment-list validates before iterating --------------------------------
cat >"$fixture/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"
printf '%s\n' '{"comments":"not-an-array"}'
exit 0
FAKE_GH
chmod +x "$fixture/bin/gh"
status=0
GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
	"$tracker" comment-list --profile github --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 4 "$status" 'comment-list against a malformed payload'
assert_error "$fixture/err" transport 'comment-list malformed is transport, not partial'

# --- --profile cannot escape the profiles directory -------------------------
# The flag bypasses the AGENTS.md route, whose grammar is enforced in
# resolve_tracker, and the name is concatenated into a path and sourced. Without
# the same grammar on the flag, a relative name runs an arbitrary file in the
# engine's process. The number of levels is computed from profiles/ rather than
# assumed: a fixed count stops reaching the root once a checkout sits deeper than
# it, and the case would then pass against an unguarded engine while still
# reading as traversal coverage.
cat >"$fixture/evil.sh" <<EVIL
printf 'sourced\n' >"$fixture/pwned"
EVIL
slashes=$(printf '%s' "$script_dir/profiles" | tr -cd /)
traversal=$(printf '../%.0s' $(seq "${#slashes}"))${fixture#/}/evil
status=0
PATH="$fixture/bin:$PATH" "$tracker" view --profile "$traversal" \
	--target example/repo 101 >"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'view with a traversing profile name'
assert_error "$fixture/err" usage 'traversing profile name'
# The grammar, named: an unknown-but-well-formed profile also exits 1 as usage,
# so without this the only discriminating assertion is the marker below.
assert_contains 'profile name must match' "$fixture/err"
[[ ! -e $fixture/pwned ]] || fail '--profile sourced a file outside profiles/'

# An empty value is a usage error too, not a silent fall-through to the
# declaration: --profile '' asked for a profile and named none.
status=0
PATH="$fixture/bin:$PATH" "$tracker" view --profile '' --target example/repo 101 \
	>"$fixture/out" 2>"$fixture/err" || status=$?
assert_exit 1 "$status" 'view with an empty profile name'
assert_error "$fixture/err" usage 'empty profile name'

# --- a CRLF declaration is valid, not malformed -----------------------------
mkdir -p "$fixture/crlf"
git -C "$fixture/crlf" init -q
printf 'issue-tracker: github\r\n' >"$fixture/crlf/AGENTS.md"
status=0
(cd "$fixture/crlf" && "$tracker" resolve) >"$fixture/out" 2>"$fixture/err" ||
	status=$?
assert_exit 0 "$status" 'resolve with a CRLF declaration'
[[ $(cat "$fixture/out") == github ]] ||
	fail "CRLF declaration resolved to '$(cat "$fixture/out")'"

printf 'tracker-test: all assertions passed\n'
