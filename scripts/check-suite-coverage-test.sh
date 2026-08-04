#!/usr/bin/env bash
set -euo pipefail

# The pre-commit hook exports a git environment for the file it is checking. A
# fixture repository built under an inherited GIT_DIR is the real repository with
# a different work tree, so every assertion below would read the wrong index.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
	GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
gate=$repo_root/scripts/check-suite-coverage.sh

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

fixture_serial=0
fixture=
last_output=

fail() {
	printf 'suite-coverage-test: %s\n' "$*" >&2
	exit 1
}

# A fixture repository shaped like this one: a plain `test` recipe listing suites
# one per line, a shebang `records` recipe that runs one suite and byte-compares a
# mirrored copy it never invokes, and glob-based lint and format recipes. Sets
# $fixture; a command substitution would run the counter in a subshell and hand
# every case the same directory.
new_fixture() {
	fixture_serial=$((fixture_serial + 1))
	local dir=$tmp_root/fixture-$fixture_serial
	mkdir -p "$dir/scripts" "$dir/.github/scripts" "$dir/mirror"
	cp "$gate" "$dir/scripts/check-suite-coverage.sh"

	# Distinct bytes per suite, so byte-identity clears the mirrored copy and
	# nothing else.
	local suite
	for suite in alpha-test.sh scripts/beta-test.sh .github/scripts/gamma-test.sh; do
		printf '#!/usr/bin/env bash\n# %s\nexit 0\n' "$suite" >"$dir/$suite"
		chmod +x "$dir/$suite"
	done
	cp "$dir/.github/scripts/gamma-test.sh" "$dir/mirror/gamma-test.sh"

	cat >"$dir/Justfile" <<'JUSTFILE'
test:
  ./alpha-test.sh
  ./scripts/beta-test.sh

records:
  #!/usr/bin/env bash
  set -euo pipefail
  ./.github/scripts/gamma-test.sh
  for asset in gamma-test.sh; do
    cmp -s ".github/scripts/$asset" "mirror/$asset" || exit 1
  done

lint:
  shellcheck alpha-test.sh scripts/*.sh .github/scripts/*.sh

format-check:
  shfmt -d alpha-test.sh scripts/*.sh
  shfmt -i 2 -d .github/scripts/*.sh

format:
  shfmt -w alpha-test.sh scripts/*.sh
  shfmt -i 2 -w .github/scripts/*.sh
JUSTFILE

	git -C "$dir" init -q -b main
	git -C "$dir" add -A
	fixture=$dir
}

# run_gate <fixture> [cwd] — records combined output, returns the gate's status.
run_gate() {
	local dir=$1 cwd=${2:-$1} status=0
	last_output=$(cd "$cwd" && "$dir/scripts/check-suite-coverage.sh" 2>&1) || status=$?
	return "$status"
}

expect_green() {
	local dir=$1 what=$2
	run_gate "$dir" || fail "$what: expected exit 0, got $?: $last_output"
}

expect_red() {
	local dir=$1 what=$2
	shift 2
	if run_gate "$dir"; then
		fail "$what: expected a non-zero exit, got 0: $last_output"
	fi
	local needle
	for needle in "$@"; do
		[[ $last_output == *"$needle"* ]] ||
			fail "$what: output did not name '$needle': $last_output"
	done
}

# A wired tree passes, and the unwired mirror is cleared by byte-identity.
new_fixture
expect_green "$fixture" 'fully wired tree'
[[ $last_output == *'mirror/gamma-test.sh'* ]] ||
	fail 'the byte-identity clearance was not reported'
[[ $last_output == *'.github/scripts/gamma-test.sh'* ]] ||
	fail 'the clearance did not name the copy it matched'

# The verdict must not depend on the caller's working directory: the gate resolves
# the repository root from its own path, which is also what keeps a bare basename
# in a recipe from resolving against some other tree.
new_fixture
expect_green "$fixture" 'run from the repository root'
root_output=$last_output
run_gate "$fixture" "$fixture/scripts" || fail "run from a subdirectory: exit $?"
[[ $last_output == "$root_output" ]] ||
	fail "the verdict changed with the working directory: $last_output"

# An untracked suite is not enumerated.
new_fixture
printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/scripts/spike-test.sh"
expect_green "$fixture" 'untracked suite'

# Deleting a suite's line from `test` is the mutation that must go red.
new_fixture
sed -i '/beta-test\.sh/d' "$fixture/Justfile"
expect_red "$fixture" 'suite dropped from test' \
	'scripts/beta-test.sh' 'executed' 'test'

# Commenting the line out must go red too. `just --dry-run` prints the comment
# verbatim, so a gate that reads its output as "what will run" is green here.
new_fixture
sed -i 's|^  ./scripts/beta-test.sh|  # ./scripts/beta-test.sh|' "$fixture/Justfile"
expect_red "$fixture" 'suite commented out of test' 'scripts/beta-test.sh' 'executed'

# An unreached suite under .github/scripts/ is pointed at `records`, not `test`.
new_fixture
sed -i '/gamma-test\.sh/d' "$fixture/Justfile"
expect_red "$fixture" 'suite dropped from records' \
	'.github/scripts/gamma-test.sh' 'records'

# Each non-execution dimension is reported on its own, and `format-check` and
# `format` are not merged: a suite the checker names and the writer does not is
# the disagreement ADR 0025 recorded.
new_fixture
sed -i 's|^  shellcheck alpha-test.sh scripts/\*.sh .github/scripts/\*.sh|  shellcheck alpha-test.sh .github/scripts/*.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'suite dropped from lint' 'scripts/beta-test.sh' 'linted'

new_fixture
sed -i 's|^  shfmt -w alpha-test.sh scripts/\*.sh|  shfmt -w alpha-test.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'suite dropped from format' 'scripts/beta-test.sh' 'formatted'

new_fixture
sed -i 's|^  shfmt -d alpha-test.sh scripts/\*.sh|  shfmt -d alpha-test.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'suite dropped from format-check' \
	'scripts/beta-test.sh' 'format-checked'

# Byte-identity is recomputed, not asserted: diverge the mirror and it stops
# clearing the copy no recipe reaches.
new_fixture
printf '# drift\n' >>"$fixture/mirror/gamma-test.sh"
git -C "$fixture" add -A
expect_red "$fixture" 'diverged mirror' 'mirror/gamma-test.sh' 'executed'

# A copy of a suite that is itself unreached clears nothing.
new_fixture
cp "$fixture/mirror/gamma-test.sh" "$fixture/mirror/delta-test.sh"
sed -i '/gamma-test\.sh/d' "$fixture/Justfile"
git -C "$fixture" add -A
expect_red "$fixture" 'copies of an unreached suite' \
	'mirror/gamma-test.sh' 'mirror/delta-test.sh'

# An enumeration that finds nothing is a broken gate, not a passing one. Untracking
# the suites leaves them all on disk, so nothing but the tracked-only enumeration
# distinguishes this from the fully wired tree.
new_fixture
git -C "$fixture" rm -q --cached -- '*-test.sh'
expect_red "$fixture" 'empty enumeration' 'no tracked'

printf 'suite-coverage-test: pass\n'
