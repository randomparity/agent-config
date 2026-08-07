#!/usr/bin/env bash
set -euo pipefail

# Every tracked *-test.sh must be reached by a Justfile recipe, in each dimension
# below. Coverage is read from `just --dry-run`, which writes to stderr, prints a
# shebang recipe's source rather than its commands, and passes recipe-body comments
# through verbatim — see docs/adr/0026-a-suite-is-reached-or-it-is-an-identical-copy.md.
# `test` and `records` share a dimension because either one running a suite is
# enough; `format-check` and `format` do not, because a suite the checker names and
# the writer does not is a finding `just format` cannot fix.
DIMENSIONS=(
	"executed:test records"
	"linted:lint"
	"format-checked:format-check"
	"formatted:format"
)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for tool in git just jq cmp; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		printf 'suite-coverage: %s is required\n' "$tool" >&2
		exit 2
	fi
done

covered=
reached_suites=
twin=

# Appends every path a recipe names to $covered. Each line is split into words with
# pathname expansion and nothing else — no eval, so a word carrying $asset stays
# literal — and abandoned at its first word beginning with #.
collect_paths() {
	local recipe=$1 output line word
	if ! output=$(just --dry-run "$recipe" 2>&1); then
		printf 'suite-coverage: just --dry-run %s failed:\n%s\n' "$recipe" "$output" >&2
		exit 1
	fi
	while IFS= read -r line; do
		for word in $line; do
			if [[ $word == '#'* ]]; then break; fi
			word=${word#./}
			if [[ -f $word ]]; then covered+=$word$'\n'; fi
		done
	done <<<"$output"
}

is_covered() {
	[[ $'\n'$covered == *$'\n'"$1"$'\n'* ]]
}

# A dimension is only separate from the others while its recipes pull in no
# others: `test: lint` would fold the linted set into the executed one and go
# green over a suite nothing runs.
assert_standalone() {
	local recipe=$1 dependencies
	if ! printf '%s' "$dump" | jq -e --arg r "$recipe" '.recipes | has($r)' >/dev/null; then
		printf 'suite-coverage: the Justfile has no recipe named %s\n' "$recipe" >&2
		printf '  a renamed recipe leaves its dimension unscanned; update DIMENSIONS\n' >&2
		exit 1
	fi
	dependencies=$(printf '%s' "$dump" | jq -r --arg r "$recipe" \
		'.recipes[$r].dependencies[].recipe')
	if [[ -n $dependencies ]]; then
		printf 'suite-coverage: recipe %s has dependencies (%s)\n' \
			"$recipe" "${dependencies//$'\n'/, }" >&2
		printf '  a scanned recipe must stand alone, so the scan cannot inherit its paths\n' >&2
		exit 1
	fi
}

# Sets $twin to a reached suite with identical bytes, if one exists.
find_twin() {
	local suite=$1 candidate
	twin=
	while IFS= read -r candidate; do
		if [[ -n $candidate && $candidate != "$suite" ]] && cmp -s "$suite" "$candidate"; then
			twin=$candidate
			return 0
		fi
	done <<<"$reached_suites"
	return 1
}

report_unreached() {
	local dimension=$1 suite=$2
	printf 'suite-coverage: %s is not %s by any recipe\n' "$suite" "$dimension" >&2
	if [[ ! -f $suite ]]; then
		printf '  it is tracked but missing from the worktree; stage the deletion\n' >&2
		return
	fi
	case $dimension in
	executed)
		if [[ $suite == .github/scripts/* ]]; then
			printf '  add ./%s to the Justfile records recipe\n' "$suite" >&2
		else
			printf '  add ./%s to the Justfile test recipe\n' "$suite" >&2
		fi
		;;
	linted) printf '  add its directory to the Justfile lint recipe\n' >&2 ;;
	format-checked) printf '  add its directory to the Justfile format-check recipe\n' >&2 ;;
	formatted) printf '  add its directory to the Justfile format recipe\n' >&2 ;;
	esac
}

# -z rather than newlines: git quotes a non-ASCII path otherwise, and an escaped
# path can never match the recipe output it is compared against.
#
# Read in a loop rather than `mapfile -d ''`: mapfile is a bash 4 builtin and the
# macOS system shell is bash 3.2, where this gate exited 127 and took `just verify`
# with it. CI runs ubuntu, so nothing caught it there.
suites=()
while IFS= read -r -d '' suite; do
	suites+=("$suite")
done < <(git ls-files -z -- '*-test.sh')
if ((${#suites[@]} == 0)); then
	printf 'suite-coverage: no tracked *-test.sh found; refusing to pass over nothing\n' >&2
	exit 1
fi
for suite in "${suites[@]}"; do
	if [[ $suite == *[[:space:]]* ]]; then
		printf 'suite-coverage: %s contains whitespace\n' "$suite" >&2
		printf '  recipe output is read by word, so no recipe can be seen to name it\n' >&2
		exit 1
	fi
done

dump=$(just --dump --dump-format json)

status=0
clearances=
for entry in "${DIMENSIONS[@]}"; do
	dimension=${entry%%:*}
	covered=
	for recipe in ${entry#*:}; do
		assert_standalone "$recipe"
		collect_paths "$recipe"
	done

	reached_suites=
	unreached=()
	for suite in "${suites[@]}"; do
		if is_covered "$suite"; then
			reached_suites+=$suite$'\n'
		else
			unreached+=("$suite")
		fi
	done

	for suite in ${unreached[@]+"${unreached[@]}"}; do
		if find_twin "$suite"; then
			clearances+="  $suite is byte-identical to $twin, which a recipe reaches"$'\n'
		else
			report_unreached "$dimension" "$suite"
			status=1
		fi
	done
done

printf 'suite-coverage: %d tracked suite(s)\n' "${#suites[@]}"
if [[ -n $clearances ]]; then
	printf 'suite-coverage: reached through an identical copy:\n'
	printf '%s' "$clearances" | sort -u
fi

exit "$status"
