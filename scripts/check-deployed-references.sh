#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
	printf 'deployed-references: rg is required\n' >&2
	exit 2
fi

if (($# > 1)); then
	printf 'usage: %s [repository-root]\n' "${0##*/}" >&2
	exit 2
fi

if (($# == 1)); then
	ROOT="$(cd "$1" && pwd)"
fi

scan_paths=(
	"$ROOT/content/skills"
	"$ROOT/agents/claude/shared"
	"$ROOT/agents/codex/shared"
	"$ROOT/agents/bob/shared"
)

for path in "${scan_paths[@]}"; do
	if [[ ! -d "$path" ]]; then
		printf 'deployed-references: deployment root is missing: %s\n' "$path" >&2
		exit 2
	fi
done

result_status=0

report_matches() { # class pattern
	local class="$1" pattern="$2" output rg_status
	set +e
	output=$(rg -n -I --hidden --with-filename -i "$pattern" "${scan_paths[@]}" 2>&1)
	rg_status=$?
	set -e
	case "$rg_status" in
	0)
		while IFS= read -r match; do
			printf 'deployed-references: %s: %s\n' "$class" "$match" >&2
		done <<<"$output"
		result_status=1
		;;
	1) ;;
	*)
		printf 'deployed-references: scan failed: %s\n' "$output" >&2
		exit 2
		;;
	esac
}

report_matches bare-adr '\bADR[[:space:]]+#?[0-9]{1,4}\b'
report_matches bare-issue '\bissue[[:space:]]+#[0-9]+\b'

path_pattern='(?<![[:alnum:]/])(?:\.\.?/)*\Kdocs/(adr|debt|superpowers/(specs|plans))/[A-Za-z0-9_.*<>/-]+\.md'
set +e
path_matches=$(rg -n -I --hidden --with-filename --pcre2 -o \
	"$path_pattern" "${scan_paths[@]}" 2>&1)
path_status=$?
set -e

case "$path_status" in
0)
	while IFS= read -r match; do
		file=${match%%:*}
		remainder=${match#*:}
		line_number=${remainder%%:*}
		candidate=${remainder#*:}
		basename=${candidate##*/}

		case "$candidate" in
		docs/adr/* | docs/debt/*)
			if [[ "$basename" == *NNNN* || "$basename" == *'<'* || "$basename" == *'*'* ]]; then
				continue
			fi
			case "$file" in
			"$ROOT/content/skills/decision-records/assets/"*) continue ;;
			esac
			line=$(sed -n "${line_number}p" "$file")
			prefix=${line%%"$candidate"*}
			prefix=$(LC_ALL=C printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')
			if [[ "$prefix" == *target-repository* ]]; then
				continue
			fi
			;;
		docs/superpowers/specs/* | docs/superpowers/plans/*)
			if [[ "$basename" == *YYYY-MM-DD* || "$basename" == *'<'* || "$basename" == *'*'* ]]; then
				continue
			fi
			;;
		esac

		printf 'deployed-references: concrete-relative-path: %s\n' "$match" >&2
		result_status=1
	done <<<"$path_matches"
	;;
1) ;;
*)
	printf 'deployed-references: path scan failed: %s\n' "$path_matches" >&2
	exit 2
	;;
esac

exit "$result_status"
