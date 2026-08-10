#!/usr/bin/env bash
set -euo pipefail

for tool in git just mktemp; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		printf 'select-verification: %s is required\n' "$tool" >&2
		exit 2
	fi
done

PATHS_FILE="$(mktemp "${TMPDIR:-/tmp}/select-verification.XXXXXX")"

cleanup() {
	rm -f "$PATHS_FILE"
}
trap cleanup EXIT

if ! git diff --cached --name-only -z --no-renames >"$PATHS_FILE"; then
	printf 'select-verification: could not read staged paths from Git\n' >&2
	exit 1
fi

add_recipe() {
	local candidate=$1 recipe
	for recipe in "${recipes[@]:-}"; do
		[[ $recipe == "$candidate" ]] && return
	done
	recipes+=("$candidate")
}

select_for_path() {
	local path=$1
	case $path in
	docs/adr/*.md)
		add_recipe records
		add_recipe public-safety
		add_recipe references-check
		;;
	docs/debt/*.md)
		add_recipe records
		add_recipe public-safety
		add_recipe references-check
		;;
	docs/*.md)
		add_recipe public-safety
		add_recipe references-check
		;;
	scripts/check-public-safety.sh)
		add_recipe lint
		add_recipe format-check
		add_recipe test-public-safety
		add_recipe suites-check
		add_recipe public-safety
		;;
	scripts/check-public-safety-test.sh)
		add_recipe lint
		add_recipe format-check
		add_recipe test-public-safety
		add_recipe suites-check
		;;
	*) deferred_paths=1 ;;
	esac
}

run_recipe() {
	local recipe=$1 started=$SECONDS
	just "$recipe"
	printf 'verification elapsed seconds: %s (%s)\n' "$((SECONDS - started))" "$recipe"
}

recipes=()
deferred_paths=0
while IFS= read -r -d '' path; do
	select_for_path "$path"
done <"$PATHS_FILE"

if ((${#recipes[@]} == 0)); then
	if ((deferred_paths)); then
		printf 'verification deferred: unclassified paths will run on push/CI\n'
	else
		printf 'verification selection: no staged paths\n'
	fi
	exit 0
fi

printf 'verification selection:'
printf ' %s' "${recipes[@]}"
printf '\n'
for recipe in "${recipes[@]}"; do
	run_recipe "$recipe"
done
if ((deferred_paths)); then
	printf 'verification deferred: unclassified paths will run on push/CI\n'
fi
