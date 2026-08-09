#!/usr/bin/env bash
set -euo pipefail

# Every tracked shell source must be reached by the applicable Justfile recipes.
# Coverage is read from `just --dry-run`, which writes to stderr, prints a shebang
# recipe's source rather than its commands, and passes recipe-body comments through
# verbatim — see ADRs 0026 and 0032.
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

DIRECT_BASH_RE=$'^#![ \t]*([^ \t]*/)?bash([ \t]|$)'
ENV_BASH_RE=$'^#![ \t]*([^ \t]*/)?env[ \t]+(bash|-S[ \t]+bash)([ \t]|$)'

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

# Sets $twin to the reached, byte-identical root twin for one of ADR 0032's
# five decision-record asset copies. No other non-suite duplicate is cleared.
find_shell_twin() {
	local shell_file=$1 candidate
	case $shell_file in
	content/skills/decision-records/assets/check-records.sh)
		candidate=.github/scripts/check-records.sh
		;;
	content/skills/decision-records/assets/check-records-test.sh)
		candidate=.github/scripts/check-records-test.sh
		;;
	content/skills/decision-records/assets/migrate-records.sh)
		candidate=.github/scripts/migrate-records.sh
		;;
	content/skills/decision-records/assets/profiles/adr.sh)
		candidate=.github/scripts/profiles/adr.sh
		;;
	content/skills/decision-records/assets/profiles/debt.sh)
		candidate=.github/scripts/profiles/debt.sh
		;;
	*) return 1 ;;
	esac
	if is_covered "$candidate" && cmp -s "$shell_file" "$candidate"; then
		twin=$candidate
		return 0
	fi
	return 1
}

report_unreached() {
	local dimension=$1 noun=$2 source=$3
	printf 'suite-coverage: %s %s is not %s by any recipe\n' \
		"$noun" "$source" "$dimension" >&2
	if [[ ! -f $source ]]; then
		printf '  it is tracked but missing from the worktree; stage the deletion\n' >&2
		return
	fi
	case $dimension in
	executed)
		if [[ $source == .github/scripts/* ]]; then
			printf '  add ./%s to the Justfile records recipe\n' "$source" >&2
		else
			printf '  add ./%s to the Justfile test recipe\n' "$source" >&2
		fi
		;;
	linted) printf '  add its directory to the Justfile lint recipe\n' >&2 ;;
	format-checked) printf '  add its directory to the Justfile format-check recipe\n' >&2 ;;
	formatted) printf '  add its directory to the Justfile format recipe\n' >&2 ;;
	esac
}

# -z rather than newlines: git quotes a non-ASCII path otherwise, and an escaped
# path can never match the recipe output it is compared against. Read in loops
# rather than `mapfile -d ''`, which the macOS Bash 3.2 lacks.
suites=()
while IFS= read -r -d '' suite; do
	suites+=("$suite")
done < <(git ls-files -z -- '*-test.sh')
if ((${#suites[@]} == 0)); then
	printf 'suite-coverage: no tracked *-test.sh found; refusing to pass over nothing\n' >&2
	exit 1
fi

shell_files=()
while IFS= read -r -d '' tracked_path; do
	if [[ $tracked_path == *.sh ]]; then
		shell_files+=("$tracked_path")
		continue
	fi
	basename=${tracked_path##*/}
	extensionless=${basename#.}
	if [[ -z $extensionless || $extensionless == *.* ]]; then
		continue
	fi
	first_line=
	if ! first_line=$(git show ":$tracked_path" | {
		line=
		IFS= read -r line || :
		printf '%s' "$line"
		cat >/dev/null
	}); then
		printf 'suite-coverage: cannot read indexed path %s\n' "$tracked_path" >&2
		exit 1
	fi
	if [[ $first_line =~ $DIRECT_BASH_RE || $first_line =~ $ENV_BASH_RE ]]; then
		shell_files+=("$tracked_path")
	fi
done < <(git ls-files -z)
if ((${#shell_files[@]} == 0)); then
	printf 'suite-coverage: no tracked shell files found; refusing to pass over nothing\n' >&2
	exit 1
fi

for shell_file in "${shell_files[@]}"; do
	if [[ $shell_file == *[[:space:]]* ]]; then
		printf 'suite-coverage: %s contains whitespace\n' "$shell_file" >&2
		printf '  recipe output is read by word, so no recipe can be seen to name it\n' >&2
		exit 1
	fi
done

dump=$(just --dump --dump-format json)

status=0
clearances=
for entry in "${DIMENSIONS[@]}"; do
	dimension=${entry%%:*}
	noun=suite
	inventory=("${suites[@]}")
	if [[ $dimension != executed ]]; then
		noun='shell file'
		inventory=("${shell_files[@]}")
	fi
	covered=
	for recipe in ${entry#*:}; do
		assert_standalone "$recipe"
		collect_paths "$recipe"
	done

	reached_suites=
	for suite in "${suites[@]}"; do
		if is_covered "$suite"; then
			reached_suites+=$suite$'\n'
		fi
	done

	for source in "${inventory[@]}"; do
		if is_covered "$source"; then
			continue
		fi
		if [[ $source == *-test.sh ]] && find_twin "$source"; then
			clearances+="  $source is byte-identical to $twin, which a recipe reaches"$'\n'
		elif [[ $noun == 'shell file' ]] && find_shell_twin "$source"; then
			clearances+="  $source is byte-identical to $twin, which a recipe reaches"$'\n'
		else
			report_unreached "$dimension" "$noun" "$source"
			status=1
		fi
	done
done

printf 'suite-coverage: %d tracked shell file(s); %d tracked suite(s)\n' \
	"${#shell_files[@]}" "${#suites[@]}"
if [[ -n $clearances ]]; then
	printf 'suite-coverage: reached through an identical copy:\n'
	printf '%s' "$clearances" | sort -u
fi

exit "$status"
