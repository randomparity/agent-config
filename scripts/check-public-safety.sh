#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ripgrep applies the contents of RIPGREP_CONFIG_PATH as arguments ahead of the
# ones below, so without this every flag this scan does not set is chosen by
# whoever set that variable -- a personal ripgreprc, a shell profile, a CI
# environment. --fixed-strings alone turns these patterns into literals that
# match nothing and this gate exits 0 on a leaking tree. Unsetting once covers
# every ripgrep this file runs, including one added later (record 0051).
unset RIPGREP_CONFIG_PATH

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
	"ATLASSIAN[A-Z0-9_]*['\"]?[[:space:]]*[=:][[:space:]]*['\"]?[A-Za-z0-9+/]{20,}"
	'gh[pousr]_[A-Za-z0-9_]{20,}'
	'sk-[A-Za-z0-9]{20,}'
	'AKIA[0-9A-Z]{16}'
	'xox[baprs]-[A-Za-z0-9-]{20,}'
)

status=0
# --text: ripgrep judges a file binary on one NUL byte and skips it while
# walking a directory, so a single NUL anywhere in a file hides every secret in
# it. --encoding none: a leading \xFF\xFE makes ripgrep transcode the file as
# UTF-16, garbling ASCII so these ASCII patterns cannot match. Both are one line
# of file content to trigger, and this gate's subject is content someone may be
# trying to get past it. The trade in --encoding none -- a file genuinely stored
# as UTF-16 stops being scanned -- is accepted in record 0051: no tracked file
# here is one, and a documented five-byte bypass is the worse half.
for pattern in "${denied_patterns[@]}"; do
	if rg -n --hidden --text --encoding none \
		--glob '!.git' --glob '!.git/**' "$pattern" "${scan_paths[@]}"; then
		printf 'public-safety: denied pattern matched: %s\n' "$pattern" >&2
		status=1
	fi
done

exit "$status"
