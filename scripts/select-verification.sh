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

is_direct_markdown_child() {
	local path=$1 prefix=$2 suffix
	[[ $path == "$prefix"* ]] || return 1
	suffix=${path#"$prefix"}
	[[ -n $suffix && $suffix != */* && $suffix == *.md ]]
}

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
	Justfile | .pre-commit-config.yaml | scripts/select-verification.sh | \
		scripts/select-verification-test.sh | scripts/check-change-aware-policy.sh | \
		scripts/check-change-aware-policy-test.sh | scripts/change-aware-observers.tsv)
		full_verification=1
		;;
	docs/superpowers/specs/*)
		if is_direct_markdown_child "$path" 'docs/superpowers/specs/'; then
			add_recipe public-safety
			add_recipe references-check
		else
			full_verification=1
		fi
		;;
	docs/superpowers/plans/*)
		if is_direct_markdown_child "$path" 'docs/superpowers/plans/'; then
			add_recipe public-safety
			add_recipe references-check
		else
			full_verification=1
		fi
		;;
	docs/adr/*)
		if is_direct_markdown_child "$path" 'docs/adr/'; then
			add_recipe records
			add_recipe public-safety
			add_recipe references-check
		else
			full_verification=1
		fi
		;;
	docs/debt/*)
		if is_direct_markdown_child "$path" 'docs/debt/'; then
			add_recipe records
			add_recipe public-safety
			add_recipe references-check
		else
			full_verification=1
		fi
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
	*) full_verification=1 ;;
	esac
}

run_recipe() {
	local recipe=$1 started=$SECONDS
	just "$recipe"
	printf 'verification elapsed seconds: %s (%s)\n' "$((SECONDS - started))" "$recipe"
}

recipes=()
full_verification=0
while IFS= read -r -d '' path; do
	if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
		select_for_path "$path"
	else
		full_verification=1
	fi
done <"$PATHS_FILE"

if ((full_verification)); then
	recipes=(ci)
fi

if ((${#recipes[@]} == 0)); then
	printf 'verification selection: no staged paths\n'
	exit 0
fi

printf 'verification selection:'
printf ' %s' "${recipes[@]}"
printf '\n'
for recipe in "${recipes[@]}"; do
	run_recipe "$recipe"
done
