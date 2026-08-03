#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
	echo "public-safety: rg is required" >&2
	exit 2
fi

if (($# > 0)); then
	scan_paths=("$@")
else
	scan_paths=("$ROOT")
fi

denied_patterns=(
	'/Users/[[:alnum:]_][[:alnum:]_.-]+'
	'/home/[[:alnum:]_][[:alnum:]_.-]+'
	'/Volumes/[[:alnum:]_][^`)]*'
	'pdx\.drc'
	'ts\.drc'
	'192\.168\.'
	'(^|[^[:alnum:]])10\.[0-9]{1,3}\.'
	'172\.(1[6-9]|2[0-9]|3[0-1])\.'
	'[[:alnum:]-]+\.atlassian\.net'
	'Basic[[:space:]]+[A-Za-z0-9+/=]{12,}'
	'ATATT[A-Za-z0-9_=.-]{20,}'
	'ATLASSIAN[A-Z0-9_]*=[[:space:]]*[A-Za-z0-9+/]{20,}={0,2}'
	'gh[pousr]_[A-Za-z0-9_]{20,}'
	'sk-[A-Za-z0-9]{20,}'
	'AKIA[0-9A-Z]{16}'
	'xox[baprs]-[A-Za-z0-9-]{20,}'
)

status=0
for pattern in "${denied_patterns[@]}"; do
	if rg -n --hidden --glob '!.git' --glob '!.git/**' "$pattern" "${scan_paths[@]}"; then
		printf 'public-safety: denied pattern matched: %s\n' "$pattern" >&2
		status=1
	fi
done

exit "$status"
