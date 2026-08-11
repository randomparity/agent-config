#!/usr/bin/env bash
set -euo pipefail

# Hooks export repository-local selectors that override every `git -C` below.
# Clear Git's reported set before this suite inspects the repository, or a
# hook-shaped environment sends `ls-files` and `checkout-index` at the hook's
# repository and the failure reads as this one being empty (ADR 0035).
while IFS= read -r variable; do
	[[ -n $variable ]] && unset "$variable"
done < <(git rev-parse --local-env-vars)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-deployed-membership.sh"

if [[ ! -x "$CHECKER" ]]; then
	printf 'checker does not exist: %s\n' "$CHECKER" >&2
	exit 127
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/deployed-membership-test.XXXXXX")"
FIXTURE="$SCRATCH/repo"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/deployed-membership-test.*)
		# One case removes read and execute from a fixture tree, which would
		# otherwise leave a directory rm cannot descend.
		chmod -R u+rwX "$SCRATCH" 2>/dev/null || :
		rm -R "$SCRATCH"
		;;
	*) printf 'deployed-membership-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

TREES=(agents/bob/shared/rules content/languages content/references)

# The fixture is checked out of the index rather than written synthetically or
# copied from the working tree. A synthetic fixture would have to restate the
# manifest, so this suite would assert the checker against a second copy of its
# own data and go stale on every manifest edit -- which is also what lets the
# pass case avoid pinning a literal member count. A working-tree copy would drag
# in the gate's own accepted false positive: untracked debris under a covered
# tree would make the fixture disagree before any case ran, so every case would
# fail for a reason unrelated to what it tests.
#
# The consequence to know: a new deployed file must be staged before this suite
# sees it, so adding one and its manifest line without `git add` shows up here as
# a missing-member on the pass case.
EXPECTED_MEMBERS=0

build_fixture() {
	local unmerged

	rm -R "$FIXTURE" 2>/dev/null || :
	mkdir -p "$FIXTURE"

	# An unmerged path lists once per stage and checkout-index refuses it, so
	# without this the run would die on git's "is unmerged" lines rather than on
	# any verdict this suite asserts.
	unmerged="$(git -C "$ROOT" ls-files -u -- "${TREES[@]}")"
	if [[ -n "$unmerged" ]]; then
		printf 'deployed-membership-test: the covered trees have unmerged paths; resolve the conflict first\n' >&2
		exit 2
	fi

	git -C "$ROOT" ls-files -z -- "${TREES[@]}" |
		git -C "$ROOT" checkout-index -f -z --stdin --prefix="$FIXTURE/"

	EXPECTED_MEMBERS="$(git -C "$ROOT" ls-files -- "${TREES[@]}" | wc -l | tr -d '[:space:]')"
	if ((EXPECTED_MEMBERS == 0)); then
		printf 'deployed-membership-test: the covered trees are empty; the suite would be vacuous\n' >&2
		exit 2
	fi
}

# Two streams, not one: check-shared-standards-test.sh merges them, which would
# let comm's disorder diagnostics or find's own "Permission denied" lines ride
# along on a run this suite calls green. Capturing them apart is what makes the
# stream split an assertion rather than a description.
run_checker() { # [locale]
	local status=0
	if (($# == 1)); then
		LC_ALL="$1" "$CHECKER" "$FIXTURE" >"$SCRATCH/out" 2>"$SCRATCH/err" || status=$?
	else
		"$CHECKER" "$FIXTURE" >"$SCRATCH/out" 2>"$SCRATCH/err" || status=$?
	fi
	return "$status"
}

fail() { # name detail...
	# The banners go through %s: bash printf parses a format string beginning
	# with `--` as its own options and dies with "invalid option", which would
	# replace every diagnostic here with a shell error about the diagnostic.
	printf 'not ok - %s: %s\n' "$1" "${*:2}" >&2
	printf '%s\n' '-- stdout --' >&2
	cat "$SCRATCH/out" >&2
	printf '%s\n' '-- stderr --' >&2
	cat "$SCRATCH/err" >&2
	exit 1
}

# The whole summary line, not a substring: <n> against the count this suite
# enumerated when it built the fixture, and <m> against the number of trees it
# lists, so the surviving-tree distinction the gate draws is testable. Silence on
# stderr is asserted too -- a green run should be provably quiet.
assert_passes() { # name [locale]
	local name="$1" expected
	shift
	if ! run_checker "$@"; then
		fail "$name" 'should pass'
	fi
	expected="deployed-membership: ok ($EXPECTED_MEMBERS declared members across ${#TREES[@]} installed trees)"
	if [[ "$(cat "$SCRATCH/out")" != "$expected" ]]; then
		fail "$name" "stdout should be exactly: $expected"
	fi
	if [[ -s "$SCRATCH/err" ]]; then
		fail "$name" 'stderr should be empty'
	fi
}

assert_fails() { # name class relative-path
	if run_checker; then
		fail "$1" 'should fail'
	fi
	if ! grep -qxF -- "deployed-membership: $2: $3" "$SCRATCH/err"; then
		fail "$1" "should report $2: $3"
	fi
	if [[ -s "$SCRATCH/out" ]]; then
		fail "$1" 'a failing run should print no summary'
	fi
}

# The whole stderr sequence, in order. Nothing else can fail a checker that
# reports its first disagreement and exits, or one whose sort took the caller's
# collation.
assert_findings() { # name locale-or-empty expected-line...
	local name="$1" locale="$2"
	shift 2
	if [[ -n "$locale" ]]; then
		run_checker "$locale" && fail "$name" 'should fail'
	else
		run_checker && fail "$name" 'should fail'
	fi
	if [[ "$(cat "$SCRATCH/err")" != "$(printf '%s\n' "$@")" ]]; then
		fail "$name" "stderr should be exactly: $*"
	fi
}

assert_absent() { # name class relative-path
	if grep -qxF -- "deployed-membership: $2: $3" "$SCRATCH/err"; then
		fail "$1" "should not report $2: $3"
	fi
}

assert_exit_two() { # name expected-message [argument...]
	local name="$1" expected="$2" code=0
	shift 2
	"$CHECKER" "$@" >"$SCRATCH/out" 2>"$SCRATCH/err" || code=$?
	if ((code != 2)); then
		fail "$name" "should exit 2, exited $code"
	fi
	if ! grep -qF -- "$expected" "$SCRATCH/err"; then
		fail "$name" "should say $expected"
	fi
}

declared_member() { # tree
	git -C "$ROOT" ls-files -- "$1" | sed -n 1p
}

build_fixture
assert_passes 'the three trees as tracked'

# One per tree: a gate that enumerated only the first would pass the other two.
for tree in "${TREES[@]}"; do
	build_fixture
	printf 'stray\n' >"$FIXTURE/$tree/unexpected.md"
	assert_fails "an undeclared file under $tree" unexpected-member "$tree/unexpected.md"
done

build_fixture
printf 'stray\n' >"$FIXTURE/content/languages/.notes.md"
assert_fails 'a dot-prefixed file' unexpected-member 'content/languages/.notes.md'

# The .ignore sits at the fixture root, not inside a tree: ripgrep applies a
# parent .ignore to descendants, so this still defeats an rg-based enumeration
# while leaving the covered tree holding exactly one planted member.
build_fixture
printf 'ignored.md\n' >"$FIXTURE/.ignore"
printf 'stray\n' >"$FIXTURE/content/languages/ignored.md"
assert_fails 'an ignored file' unexpected-member 'content/languages/ignored.md'

build_fixture
mkdir -p "$FIXTURE/content/references/nested"
printf 'stray\n' >"$FIXTURE/content/references/nested/deep.md"
assert_fails 'a file in a new subdirectory' unexpected-member 'content/references/nested/deep.md'

build_fixture
member="$(declared_member content/languages)"
ln -s "$ROOT/$member" "$FIXTURE/content/languages/link.md"
assert_findings 'an undeclared symlink to a file' '' \
	'deployed-membership: unexpected-member: content/languages/link.md' \
	'deployed-membership: non-regular-member: content/languages/link.md'

# find does not descend a symlink, so this enumerates as one path while cp -pR
# would deploy whatever the target resolves to on the user's machine.
build_fixture
ln -s "$ROOT/content/references" "$FIXTURE/content/languages/tree-link"
assert_findings 'an undeclared symlink to a directory' '' \
	'deployed-membership: unexpected-member: content/languages/tree-link' \
	'deployed-membership: non-regular-member: content/languages/tree-link'

# Declaring a path must not admit whatever it points at.
build_fixture
member="$(declared_member content/references)"
rm "$FIXTURE/$member"
ln -s "$ROOT/$member" "$FIXTURE/$member"
assert_fails 'a declared member replaced by a symlink' non-regular-member "$member"
assert_absent 'a declared member replaced by a symlink' missing-member "$member"

build_fixture
member="$(declared_member agents/bob/shared/rules)"
rm "$FIXTURE/$member"
assert_fails 'a declared member deleted' missing-member "$member"

# Zeta.md sorts before alpha.md under C and after it under en_US.UTF-8, so this
# pins the gate's own collation as well as same-class multiplicity.
build_fixture
printf 'stray\n' >"$FIXTURE/content/languages/Zeta.md"
printf 'stray\n' >"$FIXTURE/content/languages/alpha.md"
assert_findings 'two undeclared files under one tree' '' \
	'deployed-membership: unexpected-member: content/languages/Zeta.md' \
	'deployed-membership: unexpected-member: content/languages/alpha.md'

# Probed rather than matched against `locale -a`: glibc accepts en_US.UTF-8 while
# listing it as en_US.iso88591 and friends, so a name match skips a row that would
# have run. What these rows need is any locale that collates alpha before Zeta,
# which is exactly what this asks.
collating_locale=''
for candidate in en_US.UTF-8 en_US.utf8 en_GB.UTF-8; do
	if [[ "$(printf 'Zeta\nalpha\n' | LC_ALL="$candidate" sort 2>/dev/null | sed -n 1p)" == 'alpha' ]]; then
		collating_locale="$candidate"
		break
	fi
done

if [[ -n "$collating_locale" ]]; then
	build_fixture
	assert_passes 'a non-C caller locale' "$collating_locale"

	# Without the gate's own `export LC_ALL=C` this order flips, which is the
	# only row where the export is load-bearing.
	build_fixture
	printf 'stray\n' >"$FIXTURE/content/languages/Zeta.md"
	printf 'stray\n' >"$FIXTURE/content/languages/alpha.md"
	assert_findings 'ordering under a non-C caller locale' "$collating_locale" \
		'deployed-membership: unexpected-member: content/languages/Zeta.md' \
		'deployed-membership: unexpected-member: content/languages/alpha.md'
else
	printf 'deployed-membership-test: skipping the non-C locale rows: no collating locale is available\n' >&2
fi

# A checker that stopped at its first disagreement would satisfy every
# single-delta row above.
build_fixture
member="$(declared_member content/references)"
rm "$FIXTURE/$member"
printf 'stray\n' >"$FIXTURE/content/languages/unexpected.md"
assert_findings 'one unexpected and one missing in a single run' '' \
	'deployed-membership: unexpected-member: content/languages/unexpected.md' \
	"deployed-membership: missing-member: $member"

build_fixture
mkdir -p "$FIXTURE/content/instructions"
printf 'not deployed\n' >"$FIXTURE/content/instructions/notes.md"
assert_passes 'a file outside the declared trees'

# Git does not track empty directories, so deleting the sole file of a one-file
# tree removes the directory from every fresh checkout. That must read as the
# deletion it is, not as the gate being unable to run.
build_fixture
member="$(declared_member content/references)"
rm -R "$FIXTURE/content/references"
assert_fails 'a one-file tree removed entirely' missing-member "$member"

build_fixture
member="$(declared_member content/references)"
rm -R "$FIXTURE/content/references"
printf 'not a tree\n' >"$FIXTURE/content/references"
assert_fails 'a tree replaced by a regular file' missing-member "$member"
assert_absent 'a tree replaced by a regular file' unexpected-member 'content/references'

# test -d dereferences, so a bare -d filter would let this through and find would
# print the tree path itself as a member.
build_fixture
member="$(declared_member content/references)"
rm -R "$FIXTURE/content/references"
ln -s "$ROOT/content/languages" "$FIXTURE/content/references"
assert_fails 'a tree replaced by a symlink to a directory' missing-member "$member"
assert_absent 'a tree replaced by a symlink to a directory' unexpected-member 'content/references'

build_fixture
for tree in "${TREES[@]}"; do
	rm -R "${FIXTURE:?}/$tree"
done
if run_checker; then
	fail 'every declared tree removed' 'should fail'
fi
# The count, not just one match: unexpected-member multiplicity is pinned by the
# two-file row above, and without this its missing-member half is not -- a
# checker that stopped after its first missing member would pass every other row.
# EXPECTED_MEMBERS comes from the fixture build, so no second copy of the
# manifest enters the suite.
if [[ "$(grep -c 'missing-member' "$SCRATCH/err")" != "$EXPECTED_MEMBERS" ]]; then
	fail 'every declared tree removed' \
		"should report all $EXPECTED_MEMBERS declared files as missing"
fi
assert_absent 'every declared tree removed' unexpected-member 'content/instructions/notes.md'

# The only executable evidence that a fault never swallows a finding: a checker
# letting find's failure fall through as an empty enumeration would report every
# declared file as missing and pass without this row. The skip announces itself,
# so a run that did not prove the invariant is distinguishable from one that did.
if [[ "$(id -u)" -eq 0 ]]; then
	printf 'deployed-membership-test: skipping the unreadable-tree row: running as root\n' >&2
else
	build_fixture
	chmod 000 "$FIXTURE/content/languages"
	assert_exit_two 'an unreadable tree' 'could not enumerate the installed trees' "$FIXTURE"
	assert_absent 'an unreadable tree' missing-member 'content/languages/bash.md'
	chmod u+rwx "$FIXTURE/content/languages"
fi

build_fixture
assert_exit_two 'a second argument' 'usage:' "$FIXTURE" extra

assert_exit_two 'an unusable repository root' 'repository root is not a directory' \
	"$SCRATCH/no-such-root"

printf 'deployed-membership-test: ok\n'
