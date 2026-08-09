#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_NAME=scripts/change-aware-observers.tsv

if (($# > 1)); then
	printf 'usage: %s [repository-root]\n' "${0##*/}" >&2
	exit 2
fi
if (($# == 1)); then
	ROOT="$(cd "$1" && pwd)"
fi

for tool in git just jq; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		printf 'change-aware-policy: %s is required\n' "$tool" >&2
		exit 2
	fi
done

MANIFEST="$ROOT/$MANIFEST_NAME"
if [[ ! -f $MANIFEST ]]; then
	printf 'change-aware-policy: manifest is missing: %s\n' "$MANIFEST_NAME" >&2
	exit 1
fi

die() {
	printf 'change-aware-policy: %s\n' "$1" >&2
	exit 1
}

hash_dry_run() {
	local recipe=$1 output
	if ! output=$(cd "$ROOT" && just --dry-run "$recipe" 2>&1); then
		die "just --dry-run failed for $recipe"
	fi
	printf '%s\n' "$output" |
		sed -E '/^[[:space:]]*#/d; /^[[:space:]]*$/d; s/[[:space:]]+/ /g; s/^ //; s/ $//' |
		git hash-object --stdin
}

has_manifest_path() {
	local recipe=$1 path=$2 entry
	for entry in "${manifest_entries[@]}"; do
		[[ ${entry%%$'\t'*} == "$recipe" ]] || continue
		entry=${entry#*$'\t'}
		entry=${entry#*$'\t'}
		[[ ${entry%%$'\t'*} == "$path" ]] && return 0
	done
	return 1
}

manifest_entries=()
manifest_recipes=
while IFS=$'\t' read -r recipe dry_run_hash path object_hash extra; do
	[[ -z $recipe || $recipe == \#* ]] && continue
	[[ -z $dry_run_hash || -z $path || -z $object_hash || -n ${extra:-} ]] &&
		die "malformed manifest row for $recipe"
	manifest_entries+=("$recipe"$'\t'"$dry_run_hash"$'\t'"$path"$'\t'"$object_hash")
	if [[ $'\n'$manifest_recipes != *$'\n'"$recipe"$'\n'* ]]; then
		manifest_recipes+=$recipe$'\n'
	fi
done <"$MANIFEST"

dump=$(cd "$ROOT" && just --dump --dump-format json)
dependencies=$(printf '%s' "$dump" | jq -r '.recipes.verify.dependencies[].recipe')
[[ -n $dependencies ]] || die 'verify has no dependencies'

while IFS= read -r recipe; do
	[[ $'\n'$manifest_recipes == *$'\n'"$recipe"$'\n'* ]] ||
		die "verify dependency is unmanifested: $recipe"
done <<<"$dependencies"

while IFS= read -r recipe; do
	[[ -n $recipe ]] || continue
	if ! printf '%s\n' "$dependencies" | rg -qxF "$recipe"; then
		die "manifest names non-dependency recipe: $recipe"
	fi
done <<<"$manifest_recipes"

for entry in "${manifest_entries[@]}"; do
	IFS=$'\t' read -r recipe dry_run_hash path object_hash <<<"$entry"
	dry_run_actual=$(hash_dry_run "$recipe")
	[[ $dry_run_actual == "$dry_run_hash" ]] ||
		die "stale dry-run fingerprint for $recipe"
	[[ -f $ROOT/$path ]] || die "manifest path is missing: $path"
	object_actual=$(git hash-object "$ROOT/$path")
	[[ $object_actual == "$object_hash" ]] || die "stale implementation fingerprint: $path"
done

while IFS= read -r recipe; do
	output=$(cd "$ROOT" && just --dry-run "$recipe" 2>&1) || die "just --dry-run failed for $recipe"
	while IFS= read -r script; do
		script=${script#./}
		if [[ -f $ROOT/$script ]] && ! has_manifest_path "$recipe" "$script"; then
			die "dry-run script is unmanifested for $recipe: $script"
		fi
	done < <(printf '%s\n' "$output" | rg -o '(\./)?[A-Za-z0-9_./-]+\.sh' || :)
done <<<"$dependencies"

printf 'change-aware-policy: manifest matches %s verify dependencies\n' \
	"$(printf '%s\n' "$dependencies" | wc -l | tr -d ' ')"
