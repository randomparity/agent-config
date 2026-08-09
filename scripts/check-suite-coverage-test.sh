#!/usr/bin/env bash
set -euo pipefail

# Hooks export repository-local Git variables that override `git -C`. Clear
# Git's complete reported set before any fixture repository is discovered.
while IFS= read -r variable; do
	[ -n "$variable" ] || continue
	unset "$variable"
done < <(git rev-parse --local-env-vars)

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

# In-place edit that both seds agree on. BSD sed reads -i's next argument as the
# backup suffix and GNU sed does not, so a bare `sed -i SCRIPT FILE` runs SCRIPT as
# a suffix on macOS and dies on the filename. Rewriting through a temp file needs no
# -i at all. Every fixture edit below goes through this.
#
# It does not preserve the file's mode — the temp file takes the umask's, so a 755
# input comes back 644. Every call site here edits the fixture Justfile, which is 644
# and never executed; do not reach for this on the +x suite fixtures new_fixture
# creates without adding `cp -p` first.
sed_i() {
	local script=$1 file=$2 tmp=$2.sed-tmp
	sed "$script" "$file" >"$tmp" && mv "$tmp" "$file"
}

# A fixture repository shaped like this one: a plain `test` recipe listing suites
# one per line, a shebang `records` recipe that runs one suite and byte-compares a
# mirrored copy it never invokes, and glob-based lint and format recipes. Sets
# $fixture; a command substitution would run the counter in a subshell and hand
# every case the same directory.
new_fixture() {
	fixture_serial=$((fixture_serial + 1))
	local dir=$tmp_root/fixture-$fixture_serial
	mkdir -p "$dir/scripts" "$dir/.github/scripts/profiles" \
		"$dir/content/skills/decision-records/assets/profiles" "$dir/mirror"
	cp "$gate" "$dir/scripts/check-suite-coverage.sh"

	# Distinct bytes per suite, so byte-identity clears the mirrored copy and
	# nothing else.
	local suite
	for suite in alpha-test.sh scripts/beta-test.sh .github/scripts/gamma-test.sh; do
		printf '#!/usr/bin/env bash\n# %s\nexit 0\n' "$suite" >"$dir/$suite"
		chmod +x "$dir/$suite"
	done
	cp "$dir/.github/scripts/gamma-test.sh" "$dir/mirror/gamma-test.sh"

	printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/scripts/helper.sh"
	printf '#!/bin/bash\nexit 0\n' >"$dir/scripts/direct-bash"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/scripts/env-bash"
	printf '#!/usr/bin/env -S bash\nexit 0\n' >"$dir/scripts/env-split-bash"
	printf '#!/bin/bash\nexit 0\n' >"$dir/scripts/.hidden-bash"
	printf '#! /usr/bin/env bash\nexit 0\n' >"$dir/scripts/spaced-env-bash"
	printf '#!/bin/bash -e\nexit 0\n' >"$dir/scripts/direct-bash-args"
	printf '#!/usr/bin/env bash -e\nexit 0\n' >"$dir/scripts/env-bash-args"
	printf '#!/usr/bin/env -S bash -e\nexit 0\n' >"$dir/scripts/env-split-bash-args"

	printf '#!/usr/bin/env python\n' >"$dir/scripts/python-tool"
	printf '#!/usr/bin/not-bash\n' >"$dir/scripts/not-bash"
	printf '#!/usr/bin/env python bash\n' >"$dir/scripts/later-bash"
	printf 'plain text\n' >"$dir/scripts/no-shebang"
	printf '#!/bin/bash\n' >"$dir/scripts/.hidden.local"
	: >"$dir/scripts/empty-tool"
	printf '#!/usr/bin/env python\n' >"$dir/scripts/large-python"
	dd if=/dev/zero bs=1024 count=128 >>"$dir/scripts/large-python" 2>/dev/null

	local asset root_asset skill_asset
	for asset in check-records.sh check-records-test.sh migrate-records.sh \
		profiles/adr.sh profiles/debt.sh; do
		root_asset=$dir/.github/scripts/$asset
		skill_asset=$dir/content/skills/decision-records/assets/$asset
		printf '#!/usr/bin/env bash\n# %s\nexit 0\n' "$asset" >"$root_asset"
		cp "$root_asset" "$skill_asset"
	done

	cat >"$dir/Justfile" <<'JUSTFILE'
test:
  ./alpha-test.sh
  ./scripts/beta-test.sh

records:
  #!/usr/bin/env bash
  set -euo pipefail
  ./.github/scripts/gamma-test.sh
  ./.github/scripts/check-records-test.sh
  for asset in gamma-test.sh; do
    cmp -s ".github/scripts/$asset" "mirror/$asset" || exit 1
  done

lint:
  shellcheck alpha-test.sh scripts/*.sh .github/scripts/*.sh .github/scripts/profiles/*.sh
  shellcheck scripts/direct-bash scripts/env-bash scripts/env-split-bash scripts/.hidden-bash \
    scripts/spaced-env-bash scripts/direct-bash-args scripts/env-bash-args \
    scripts/env-split-bash-args

format-check:
  shfmt -d alpha-test.sh scripts/*.sh
  shfmt -i 2 -d .github/scripts/*.sh .github/scripts/profiles/*.sh
  shfmt -d scripts/direct-bash scripts/env-bash scripts/env-split-bash scripts/.hidden-bash \
    scripts/spaced-env-bash scripts/direct-bash-args scripts/env-bash-args \
    scripts/env-split-bash-args

format:
  shfmt -w alpha-test.sh scripts/*.sh
  shfmt -i 2 -w .github/scripts/*.sh .github/scripts/profiles/*.sh
  shfmt -w scripts/direct-bash scripts/env-bash scripts/env-split-bash scripts/.hidden-bash \
    scripts/spaced-env-bash scripts/direct-bash-args scripts/env-bash-args \
    scripts/env-split-bash-args
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
for source in direct-bash env-bash env-split-bash .hidden-bash spaced-env-bash \
	direct-bash-args env-bash-args env-split-bash-args; do
	new_fixture
	sed_i "s| scripts/$source||g" "$fixture/Justfile"
	expect_red "$fixture" "$source removed from lint" "scripts/$source" 'linted'
done

# A non-suite *.sh path is checked independently in every static-analysis
# dimension. Keep beta-test.sh named so each mutation isolates helper.sh.
new_fixture
sed_i 's|^  shellcheck alpha-test.sh scripts/\*.sh|  shellcheck alpha-test.sh scripts/beta-test.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'shell file dropped from lint' 'scripts/helper.sh' 'linted'

new_fixture
sed_i 's|^  shfmt -d alpha-test.sh scripts/\*.sh|  shfmt -d alpha-test.sh scripts/beta-test.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'shell file dropped from format-check' \
	'scripts/helper.sh' 'format-checked'

new_fixture
sed_i 's|^  shfmt -w alpha-test.sh scripts/\*.sh|  shfmt -w alpha-test.sh scripts/beta-test.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'shell file dropped from format' 'scripts/helper.sh' 'formatted'

# Only ADR 0032's five fixed asset/root pairs receive non-suite shell-copy
# clearance, and the bytes are compared on every run.
new_fixture
printf '# drift\n' >>"$fixture/content/skills/decision-records/assets/migrate-records.sh"
git -C "$fixture" add -A
expect_red "$fixture" 'diverged mapped shell copy' \
	'content/skills/decision-records/assets/migrate-records.sh' 'linted'

new_fixture
cp "$fixture/.github/scripts/check-records.sh" "$fixture/mirror/check-records.sh"
git -C "$fixture" add -A
expect_red "$fixture" 'unmapped identical shell copy' 'mirror/check-records.sh' 'linted'

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

# A contributor-controlled extensionless blob cannot make Bash retain an
# unbounded first line while the gate classifies its shebang.
new_fixture
dd if=/dev/zero bs=4097 count=1 2>/dev/null | tr '\000' x \
	>"$fixture/scripts/overlong-first-line"
git -C "$fixture" add -A
expect_red "$fixture" 'overlong indexed first line' \
	'scripts/overlong-first-line' 'exceeds 4096 characters'

# Deleting a suite's line from `test` is the mutation that must go red.
new_fixture
sed_i '/beta-test\.sh/d' "$fixture/Justfile"
expect_red "$fixture" 'suite dropped from test' \
	'scripts/beta-test.sh' 'executed' 'Justfile test recipe'

# Commenting the line out must go red too. `just --dry-run` prints the comment
# verbatim, so a gate that reads its output as "what will run" is green here.
new_fixture
sed_i 's|^  ./scripts/beta-test.sh|  # ./scripts/beta-test.sh|' "$fixture/Justfile"
expect_red "$fixture" 'suite commented out of test' 'scripts/beta-test.sh' 'executed'

# An unreached suite under .github/scripts/ is pointed at `records`, not `test`.
new_fixture
sed_i '/gamma-test\.sh/d' "$fixture/Justfile"
expect_red "$fixture" 'suite dropped from records' \
	'.github/scripts/gamma-test.sh' 'records'

# Each non-execution dimension is reported on its own, and `format-check` and
# `format` are not merged: a suite the checker names and the writer does not is
# the disagreement ADR 0025 recorded.
new_fixture
sed_i 's| scripts/\*.sh | |' "$fixture/Justfile"
expect_red "$fixture" 'suite dropped from lint' 'scripts/beta-test.sh' 'linted'

new_fixture
sed_i 's|^  shfmt -w alpha-test.sh scripts/\*.sh|  shfmt -w alpha-test.sh|' \
	"$fixture/Justfile"
expect_red "$fixture" 'suite dropped from format' 'scripts/beta-test.sh' 'formatted'

new_fixture
sed_i 's|^  shfmt -d alpha-test.sh scripts/\*.sh|  shfmt -d alpha-test.sh|' \
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
sed_i '/gamma-test\.sh/d' "$fixture/Justfile"
git -C "$fixture" add -A
expect_red "$fixture" 'copies of an unreached suite' \
	'mirror/gamma-test.sh' 'mirror/delta-test.sh'

# A suite name carrying a glob metacharacter is compared literally. Read as a
# pattern instead, this one matches .github/scripts/gamma-test.sh in the covered
# set and is cleared with no clearance line to show for it.
new_fixture
metachar='.github/scripts/g*a-test.sh'
printf '#!/usr/bin/env bash\n# metachar\nexit 0\n' >"$fixture/$metachar"
git -C "$fixture" add -A
expect_red "$fixture" 'glob metacharacter in a suite name' "$metachar" 'executed'

# A suite whose name carries whitespace cannot be matched against output read by
# word, so it is refused by name instead of reported as unwired.
new_fixture
printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/scripts/two words-test.sh"
git -C "$fixture" add -A
expect_red "$fixture" 'whitespace in a suite name' \
	'two words-test.sh' 'contains whitespace'

# A suite still in the index but gone from the worktree is named as such, rather
# than being reported as wiring the contributor forgot.
new_fixture
rm "$fixture/scripts/beta-test.sh"
expect_red "$fixture" 'suite deleted but not staged' \
	'scripts/beta-test.sh' 'missing from the worktree'

# A scanned recipe that pulls in another folds that recipe's dimension into its
# own, so the gate refuses to read it rather than reporting over a merged set.
new_fixture
sed_i 's|^test:$|test: lint|' "$fixture/Justfile"
expect_red "$fixture" 'scanned recipe with a dependency' \
	'recipe test has dependencies (lint)' 'stand alone'

# A renamed recipe leaves its dimension unscanned, which the gate must say rather
# than dying inside the dump lookup.
new_fixture
sed_i 's|^lint:$|linting:|' "$fixture/Justfile"
expect_red "$fixture" 'renamed recipe' 'no recipe named lint'

# A non-ASCII suite name is enumerated as its own bytes. Read through git's default
# quoting it arrives escaped, matches the recipe output for no path, and is reported
# both as unreached and as missing from the worktree.
new_fixture
accented=$fixture/scripts/café-test.sh
printf '#!/usr/bin/env bash\n# accented\nexit 0\n' >"$accented"
# A backslash-newline, not \n: the backslash-newline is POSIX and every sed takes it,
# whereas \n in a replacement is a GNU extension no BSD sed is required to support.
# Apple's current sed does happen to expand it — probed on this host, byte-identical
# output — so this is portability to the seds that do not, not a fix for a live break.
sed_i 's|^  ./scripts/beta-test.sh|  ./scripts/beta-test.sh\
  ./scripts/café-test.sh|' "$fixture/Justfile"
git -C "$fixture" add -A
expect_green "$fixture" 'non-ASCII suite name'

# An enumeration that finds nothing is a broken gate, not a passing one. Untracking
# the suites leaves them all on disk, so nothing but the tracked-only enumeration
# distinguishes this from the fully wired tree.
new_fixture
git -C "$fixture" rm -q --cached -- '*-test.sh'
expect_red "$fixture" 'empty enumeration' 'no tracked'

printf 'suite-coverage-test: pass\n'
