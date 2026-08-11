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

# The fourth wholesale-installed tree, kept out of TREES on purpose: EXPECTED_MEMBERS
# is the file-granularity count and must not absorb the 96 files under this one.
SKILL_TREE='content/skills'

# Emitted once after every finding whenever an unexpected member was reported.
# Held here so the expected sequences below stay readable.
REMEDY='deployed-membership: delete an unexpected member, or declare it here only if it is meant to install for every user'

# The skills half's own remedy. Separate text, because the two blocks fire
# independently and a reader given the file half's line would not know which
# finding it addressed.
SKILL_REMEDY='deployed-membership: delete an unexpected entry, or declare it here only if it is a skill meant to install for every user'

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
EXPECTED_SKILL_DIRECTORIES=0

# The optional argument names a fixture root other than the default, which is how
# the bracket-expression row below checks the gate out under a path holding fnmatch
# metacharacters.
build_fixture() { # [fixture-root]
	local unmerged

	FIXTURE="${1:-$SCRATCH/repo}"
	rm -R "$FIXTURE" 2>/dev/null || :
	mkdir -p "$FIXTURE"

	# An unmerged path lists once per stage and checkout-index refuses it, so
	# without this the run would die on git's "is unmerged" lines rather than on
	# any verdict this suite asserts.
	unmerged="$(git -C "$ROOT" ls-files -u -- "${TREES[@]}" "$SKILL_TREE")"
	if [[ -n "$unmerged" ]]; then
		printf 'deployed-membership-test: the covered trees have unmerged paths; resolve the conflict first\n' >&2
		exit 2
	fi

	git -C "$ROOT" ls-files -z -- "${TREES[@]}" "$SKILL_TREE" |
		git -C "$ROOT" checkout-index -f -z --stdin --prefix="$FIXTURE/"

	EXPECTED_MEMBERS="$(git -C "$ROOT" ls-files -- "${TREES[@]}" | wc -l | tr -d '[:space:]')"
	if ((EXPECTED_MEMBERS == 0)); then
		printf 'deployed-membership-test: the covered trees are empty; the suite would be vacuous\n' >&2
		exit 2
	fi

	# NF>3 rather than every third field: a tracked file directly under the skills
	# tree has three fields, and counting it as a directory would inflate this to 37
	# while the checker's list stayed 36 -- so the pass row would fail on a summary
	# mismatch instead of on the unexpected-skill-entry pair that is the real answer.
	EXPECTED_SKILL_DIRECTORIES="$(git -C "$ROOT" ls-files -- "$SKILL_TREE" |
		awk -F/ 'NF>3 {print $3}' | sort -u | wc -l | tr -d '[:space:]')"
	if ((EXPECTED_SKILL_DIRECTORIES == 0)); then
		printf 'deployed-membership-test: the skills tree is empty; the suite would be vacuous\n' >&2
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
	expected="deployed-membership: ok ($EXPECTED_MEMBERS declared members across ${#TREES[@]} installed trees, $EXPECTED_SKILL_DIRECTORIES declared skill directories in $SKILL_TREE)"
	if [[ "$(cat "$SCRATCH/out")" != "$expected" ]]; then
		fail "$name" "stdout should be exactly: $expected"
	fi
	if [[ -s "$SCRATCH/err" ]]; then
		fail "$name" 'stderr should be empty'
	fi
}

# Exactly 1, not merely non-zero: exit 1 means a difference was found and exit 2
# means the gate could not run, and ADR 0045 turns on the fault class never
# swallowing a finding. Without pinning the value, every finding row here would
# be satisfied by a checker that printed the right lines and exited 2.
assert_fails() { # name class relative-path
	local code=0
	run_checker || code=$?
	if ((code != 1)); then
		fail "$1" "should exit 1, exited $code"
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
	local name="$1" locale="$2" code=0
	shift 2
	if [[ -n "$locale" ]]; then
		run_checker "$locale" || code=$?
	else
		run_checker || code=$?
	fi
	if ((code != 1)); then
		fail "$name" "should exit 1, exited $code"
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

# The first declared skill directory, taken from the index for the reason the member
# helper is: a literal here would be a second copy of the checker's list.
#
# awk drains its input rather than `exit`-ing on the first match. Under this suite's
# `pipefail`, terminating the producer early would leave `git ls-files` writing into a
# closed pipe once the tree outgrows one pipe buffer of path text, and the resulting 141
# would surface as an errexit-fatal assignment with no `not ok -` banner naming a row.
declared_skill() {
	git -C "$ROOT" ls-files -- "$SKILL_TREE" | awk -F/ 'NF>3 && !seen++ {print $3}'
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
	'deployed-membership: non-regular-member: content/languages/link.md' \
	"$REMEDY"

# find does not descend a symlink, so this enumerates as one path while cp -pR
# would deploy whatever the target resolves to on the user's machine.
build_fixture
ln -s "$ROOT/content/references" "$FIXTURE/content/languages/tree-link"
assert_findings 'an undeclared symlink to a directory' '' \
	'deployed-membership: unexpected-member: content/languages/tree-link' \
	'deployed-membership: non-regular-member: content/languages/tree-link' \
	"$REMEDY"

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
	'deployed-membership: unexpected-member: content/languages/alpha.md' \
	"$REMEDY"

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
		'deployed-membership: unexpected-member: content/languages/alpha.md' \
		"$REMEDY"
else
	printf 'deployed-membership-test: skipping the non-C locale rows: no collating locale is available\n' >&2
fi

# The only row that produces two non-regular members, and the only one that puts
# a non-regular finding and a missing finding in the same run: without it neither
# that class's multiplicity nor the order between those two blocks is pinned.
build_fixture
member="$(declared_member content/references)"
rm "$FIXTURE/$member"
ln -s "$ROOT/$(declared_member content/languages)" "$FIXTURE/content/languages/link-a.md"
ln -s "$ROOT/$(declared_member content/languages)" "$FIXTURE/content/languages/link-b.md"
assert_findings 'two non-regular members beside a missing one' '' \
	'deployed-membership: unexpected-member: content/languages/link-a.md' \
	'deployed-membership: unexpected-member: content/languages/link-b.md' \
	'deployed-membership: non-regular-member: content/languages/link-a.md' \
	'deployed-membership: non-regular-member: content/languages/link-b.md' \
	"deployed-membership: missing-member: $member" \
	"$REMEDY"

# A checker that stopped at its first disagreement would satisfy every
# single-delta row above.
build_fixture
member="$(declared_member content/references)"
rm "$FIXTURE/$member"
printf 'stray\n' >"$FIXTURE/content/languages/unexpected.md"
assert_findings 'one unexpected and one missing in a single run' '' \
	'deployed-membership: unexpected-member: content/languages/unexpected.md' \
	"deployed-membership: missing-member: $member" \
	"$REMEDY"

# The shape that would otherwise print ok over a file that ships: a directory
# name holding a newline splits one find record into two, and here both halves
# equal declared entries, so sort -u collapses them and the undeclared payload
# disappears from the comparison entirely.
build_fixture
mkdir -p "$FIXTURE/content/languages/$(printf 'bash.md\ncontent')/languages"
printf 'payload\n' >"$FIXTURE/content/languages/$(printf 'bash.md\ncontent')/languages/python.md"
assert_exit_two 'a member path containing a newline' \
	'a member path contains a newline and cannot be compared' "$FIXTURE"

build_fixture
mkdir -p "$FIXTURE/content/instructions"
printf 'not deployed\n' >"$FIXTURE/content/instructions/notes.md"
assert_passes 'a file outside the declared trees'

# --- content/skills, compared at directory granularity (ADR 0054) -------------
#
# The rows below are the skills half's counterparts of the file half's above. Each
# pins a class the file half already pins at its own granularity, and the ones that
# have no counterpart -- the tree replaced by a regular file, the ordering between
# the two halves' blocks -- say so where they sit.

build_fixture
mkdir -p "$FIXTURE/$SKILL_TREE/undeclared-skill"
printf 'payload\n' >"$FIXTURE/$SKILL_TREE/undeclared-skill/SKILL.md"
assert_fails 'a new undeclared skill directory' unexpected-skill-entry \
	"$SKILL_TREE/undeclared-skill"

# find reads no ignore rules and skips no dot-prefixed entry, and cp -pR ships both.
# Neither case exists on the live tree, so a fixture is the only place either can be
# shown to work -- and they are the two an rg-based enumeration would silently drop.
build_fixture
mkdir -p "$FIXTURE/$SKILL_TREE/.hidden-skill"
assert_fails 'a dot-prefixed undeclared directory' unexpected-skill-entry \
	"$SKILL_TREE/.hidden-skill"

build_fixture
printf 'ignored-skill\n' >"$FIXTURE/.ignore"
mkdir -p "$FIXTURE/$SKILL_TREE/ignored-skill"
assert_fails 'an ignored undeclared directory' unexpected-skill-entry \
	"$SKILL_TREE/ignored-skill"

build_fixture
skill="$(declared_skill)"
rm -R "${FIXTURE:?}/$SKILL_TREE/${skill:?}"
assert_fails 'a declared skill directory removed' missing-skill-directory "$SKILL_TREE/$skill"

# A top-level entry that is not a directory is both undeclared and the wrong shape,
# and the two findings are true on different terms -- so both lines, as the file
# half emits unexpected-member beside non-regular-member.
build_fixture
printf 'stray\n' >"$FIXTURE/$SKILL_TREE/README.md"
assert_findings 'a stray top-level file' '' \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/README.md" \
	"deployed-membership: non-directory-skill-entry: $SKILL_TREE/README.md" \
	"$SKILL_REMEDY"

# Declaring a name must not admit whatever it points at: find -mindepth 1 does not
# descend a symlink, so this enumerates as one entry while cp -pR would deploy the
# target's whole subtree. It is present, so it is not missing.
build_fixture
skill="$(declared_skill)"
rm -R "${FIXTURE:?}/$SKILL_TREE/${skill:?}"
ln -s "$ROOT/content/references" "$FIXTURE/$SKILL_TREE/$skill"
assert_fails 'a declared skill directory replaced by a symlink' non-directory-skill-entry \
	"$SKILL_TREE/$skill"
assert_absent 'a declared skill directory replaced by a symlink' missing-skill-directory \
	"$SKILL_TREE/$skill"

# Zeta sorts before alpha under C and after it elsewhere, so this pins the gate's own
# collation as well as same-class multiplicity.
build_fixture
mkdir -p "$FIXTURE/$SKILL_TREE/Zeta-skill" "$FIXTURE/$SKILL_TREE/alpha-skill"
assert_findings 'two undeclared skill directories' '' \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/Zeta-skill" \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/alpha-skill" \
	"$SKILL_REMEDY"

# A checker that stopped at its first skills disagreement would satisfy every
# single-delta row above.
build_fixture
skill="$(declared_skill)"
mkdir -p "$FIXTURE/$SKILL_TREE/undeclared-skill"
rm -R "${FIXTURE:?}/$SKILL_TREE/${skill:?}"
assert_findings 'one undeclared and one removed skill directory' '' \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/undeclared-skill" \
	"deployed-membership: missing-skill-directory: $SKILL_TREE/$skill" \
	"$SKILL_REMEDY"

# The only row producing two non-directory entries, and the only one putting a
# non-directory finding and a missing finding in the same run: without it neither that
# class's multiplicity nor the order between those two blocks is pinned.
build_fixture
skill="$(declared_skill)"
printf 'stray\n' >"$FIXTURE/$SKILL_TREE/AAA.md"
printf 'stray\n' >"$FIXTURE/$SKILL_TREE/BBB.md"
rm -R "${FIXTURE:?}/$SKILL_TREE/${skill:?}"
assert_findings 'two stray files beside a removed skill directory' '' \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/AAA.md" \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/BBB.md" \
	"deployed-membership: non-directory-skill-entry: $SKILL_TREE/AAA.md" \
	"deployed-membership: non-directory-skill-entry: $SKILL_TREE/BBB.md" \
	"deployed-membership: missing-skill-directory: $SKILL_TREE/$skill" \
	"$SKILL_REMEDY"

# The residual, asserted rather than assumed: membership *inside* a skill directory is
# deliberately ungated (ADR 0054), so this has to keep passing. Without the row a later
# widening to per-file declaration would look like a bug fix rather than a scope change.
build_fixture
skill="$(declared_skill)"
printf 'payload\n' >"$FIXTURE/$SKILL_TREE/$skill/extra-asset.md"
assert_passes 'a file added inside a declared skill directory'

# Both halves of the split name a declared directory, so a line-delimited comparison
# would collapse them under sort -u and print ok over a directory cp -pR ships.
build_fixture
mkdir -p "$FIXTURE/$SKILL_TREE/$(printf 'brainstorming\ncampaign')"
assert_exit_two 'a skill directory name containing a newline' \
	'a skill directory name contains a newline and cannot be compared' "$FIXTURE"

# Git tracks no empty directory, so removing every skill would remove the tree. That
# must read as the deletion it is, not as the gate being unable to run.
build_fixture
rm -R "${FIXTURE:?}/$SKILL_TREE"
if run_checker; then
	fail 'the skills tree removed' 'should fail'
fi
if [[ "$(grep -c 'missing-skill-directory' "$SCRATCH/err")" != "$EXPECTED_SKILL_DIRECTORIES" ]]; then
	fail 'the skills tree removed' \
		"should report all $EXPECTED_SKILL_DIRECTORIES declared directories as missing"
fi
if [[ "$(grep -cv 'missing-skill-directory' "$SCRATCH/err")" != '0' ]]; then
	fail 'the skills tree removed' 'should report nothing but missing skill directories'
fi

build_fixture
rm -R "${FIXTURE:?}/$SKILL_TREE"
printf 'not a tree\n' >"$FIXTURE/$SKILL_TREE"
skill="$(declared_skill)"
assert_fails 'the skills tree replaced by a regular file' missing-skill-directory \
	"$SKILL_TREE/$skill"
assert_absent 'the skills tree replaced by a regular file' unexpected-skill-entry "$SKILL_TREE"

# test -d dereferences, so a bare -d filter would walk the link and declare the
# target's children members of this repository's tree.
build_fixture
rm -R "${FIXTURE:?}/$SKILL_TREE"
ln -s "$ROOT/content/skills" "$FIXTURE/$SKILL_TREE"
skill="$(declared_skill)"
assert_fails 'the skills tree replaced by a symlink to a directory' missing-skill-directory \
	"$SKILL_TREE/$skill"
assert_absent 'the skills tree replaced by a symlink to a directory' unexpected-skill-entry \
	"$SKILL_TREE/$skill"

# The two halves' blocks in one run, in order: file findings, the file remedy, then the
# skills findings and the skills remedy. This is what keeps every expected sequence
# above -- all of which predate this change -- asserting the same bytes.
build_fixture
printf 'stray\n' >"$FIXTURE/content/languages/unexpected.md"
mkdir -p "$FIXTURE/$SKILL_TREE/undeclared-skill"
assert_findings 'a three-tree finding and a skills finding in one run' '' \
	'deployed-membership: unexpected-member: content/languages/unexpected.md' \
	"$REMEDY" \
	"deployed-membership: unexpected-skill-entry: $SKILL_TREE/undeclared-skill" \
	"$SKILL_REMEDY"

# The root is excluded by depth, not by matching a pattern against it. `! -path "$root"`
# matches by fnmatch, so a root holding a well-formed bracket expression does not match
# itself: find then prints the tree root and none of its children, and the gate emits one
# unexpected entry beside every declared name as missing. This row is the form-pin.
bracket_root="$SCRATCH/br[ab]d"
mkdir -p "$bracket_root"
build_fixture "$bracket_root/repo"
assert_passes 'a fixture root holding a bracket expression'
build_fixture

# An environment that breaks the gate's own I/O must read as "could not run",
# never as "found a difference": exit 1 is reserved for a membership difference,
# and a bare tool diagnostic with no deployed-membership: line is not something
# an operator or an unattended agent can act on. Both halves are mocked on PATH
# rather than simulated, because the failure is in what the tools return.
#
# Root skips: it writes to a mode-555 directory regardless.
mock_bin="$SCRATCH/mockbin"
mkdir -p "$mock_bin"
# Under SCRATCH so this suite's own cleanup, which restores write permission
# first, reclaims the mode-555 directory the mock leaves behind.
export SCRATCH_MOCK_WORKSPACE="$SCRATCH/readonly-workspace"

assert_environment_fault() { # name mock-name mock-body
	local code=0
	printf '#!/usr/bin/env bash\n%s\n' "$3" >"$mock_bin/$2"
	chmod +x "$mock_bin/$2"
	PATH="$mock_bin:$PATH" "$CHECKER" "$FIXTURE" >"$SCRATCH/out" 2>"$SCRATCH/err" || code=$?
	rm -f "$mock_bin/$2"
	if ((code != 2)); then
		fail "$1" "should exit 2, exited $code"
	fi
	if ! grep -q '^deployed-membership: ' "$SCRATCH/err"; then
		fail "$1" 'should name itself rather than leaking a bare tool diagnostic'
	fi
}

# The unconditional mock above is consumed by the three-tree half's first call, so it
# says nothing about whether the skills half's calls are routed to `fault` too. This one
# discriminates on its operands -- only the skills workspace files carry a `skill-`
# prefix -- and delegates otherwise, so it lands in exactly one half by construction,
# with no counter and no dependence on which half the script computes first. It asserts
# the exact message rather than the `deployed-membership:` prefix, which is what fails
# the row if it ever lands in the wrong half.
assert_discriminating_fault() { # name tool operand-pattern expected-message
	local name="$1" tool="$2" pattern="$3" expected="$4" code=0

	# The real tool is resolved here, before $mock_bin reaches PATH, and baked into the
	# mock as an absolute path -- the shape check-skill-layout-test.sh already uses for
	# its shims. A mock ending `exec "$tool" "$@"` would find itself again on the PATH it
	# runs under and fork without bound, and a PATH-stripping guard only holds while the
	# mock directory is PATH's first element. What that costs is not a red row: it is a
	# CI job consumed to its timeout, with no `not ok -` banner and no
	# `deployed-membership:` line for an operator to read.
	printf '#!/usr/bin/env bash\ntool=%s\npattern=%s\nreal=%s\n' \
		"$tool" "$pattern" "$(command -v "$tool")" >"$mock_bin/$tool"
	cat >>"$mock_bin/$tool" <<'MOCK'
for arg in "$@"; do
	case "$arg" in
	$pattern)
		printf '%s: refusing the skills operand
' "$tool" >&2
		exit 1
		;;
	esac
done
exec "$real" "$@"
MOCK
	chmod +x "$mock_bin/$tool"
	PATH="$mock_bin:$PATH" "$CHECKER" "$FIXTURE" >"$SCRATCH/out" 2>"$SCRATCH/err" || code=$?
	rm -f "$mock_bin/$tool"
	if ((code != 2)); then
		fail "$name" "should exit 2, exited $code"
	fi
	if ! grep -qF -- "deployed-membership: $expected" "$SCRATCH/err"; then
		fail "$name" "should say $expected"
	fi
}

if [[ "$(id -u)" -eq 0 ]]; then
	printf 'deployed-membership-test: skipping the unwritable-workspace row: running as root\n' >&2
else
	build_fixture
	assert_environment_fault 'an unwritable workspace' mktemp \
		"dir=\"\$SCRATCH_MOCK_WORKSPACE\"; mkdir -p \"\$dir\"; chmod 555 \"\$dir\"; printf '%s\\n' \"\$dir\""
fi

build_fixture
assert_environment_fault 'a comparison that could not run' comm 'exit 1'

# Both skills comparisons take the same two operands, so one mock reaches both and this
# row proves the pair rather than either alone: dropping just one call's `|| fault`
# leaves the other to fault with the same message. Dropping both is what it catches.
build_fixture
assert_discriminating_fault 'a skills comparison that could not run' comm '*/skill-*' \
	'could not compare the enumerated skill directories against the declared set'

# The two enumerated-name sorts share a message, so each needs its own operand pattern
# or the surviving one masks the other's reverted guard.
build_fixture
assert_discriminating_fault 'the skills present sort could not run' sort '*/skill-present*' \
	'could not sort the enumerated skill directories'

build_fixture
assert_discriminating_fault 'the skills non-directory sort could not run' sort \
	'*/skill-non-directory*' 'could not sort the enumerated skill directories'

# POSIXLY_CORRECT stops getopt permuting argv, which is what would turn an option
# written after a file operand into another input file. The environment must not
# reach this verdict any more than the caller's locale does.
build_fixture
POSIXLY_CORRECT=1 "$CHECKER" "$FIXTURE" >"$SCRATCH/out" 2>"$SCRATCH/err" || :
if [[ "$(cat "$SCRATCH/out")" != "deployed-membership: ok ($EXPECTED_MEMBERS declared members across ${#TREES[@]} installed trees, $EXPECTED_SKILL_DIRECTORIES declared skill directories in $SKILL_TREE)" ]]; then
	fail 'a POSIXLY_CORRECT caller' 'should pass unchanged'
fi
if [[ -s "$SCRATCH/err" ]]; then
	fail 'a POSIXLY_CORRECT caller' 'stderr should be empty'
fi

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

# The file outside the trees is planted in this fixture on purpose. With no tree
# surviving the filter, find must not run at all: GNU find with no path operand
# walks the current directory instead, and this is the row that would catch it.
build_fixture
mkdir -p "$FIXTURE/content/instructions"
printf 'not deployed\n' >"$FIXTURE/content/instructions/notes.md"
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
# Every line, not just the one path: a find that walked the fixture root would
# report paths this row cannot enumerate in advance, and the remedy line would
# appear beside them.
if [[ "$(grep -cv 'missing-member' "$SCRATCH/err")" != '0' ]]; then
	fail 'every declared tree removed' 'should report nothing but missing members'
fi

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

	build_fixture
	chmod 000 "$FIXTURE/$SKILL_TREE"
	assert_exit_two 'an unreadable skills tree' 'could not enumerate the skills tree' "$FIXTURE"
	assert_absent 'an unreadable skills tree' missing-skill-directory "$SKILL_TREE/$(declared_skill)"
	chmod u+rwx "$FIXTURE/$SKILL_TREE"

	# Every comparison completes before any finding is emitted, so a skills-side fault
	# withholds the three-tree findings of the same run. ADR 0054 records that as a
	# disclosed consequence; this is what pins it, and no other row combines the two.
	build_fixture
	printf 'stray\n' >"$FIXTURE/content/languages/unexpected.md"
	chmod 000 "$FIXTURE/$SKILL_TREE"
	assert_exit_two 'a skills fault beside a three-tree finding' \
		'could not enumerate the skills tree' "$FIXTURE"
	assert_absent 'a skills fault beside a three-tree finding' unexpected-member \
		'content/languages/unexpected.md'
	chmod u+rwx "$FIXTURE/$SKILL_TREE"
fi

build_fixture
assert_exit_two 'a second argument' 'usage:' "$FIXTURE" extra

assert_exit_two 'an unusable repository root' 'repository root is not a directory' \
	"$SCRATCH/no-such-root"

printf 'deployed-membership-test: ok\n'
