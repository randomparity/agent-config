#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-public-safety.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/public-safety-test.XXXXXX")"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/public-safety-test.*) rm -R "$SCRATCH" ;;
	*) printf 'public-safety-test: refusing cleanup outside scratch root: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

mkdir -p "$SCRATCH/repo"
printf 'gitdir: /Vol%s/Private Disk/repo/.git/worktrees/example\n' 'umes' >"$SCRATCH/repo/.git"
printf 'public content\n' >"$SCRATCH/repo/README.md"

if ! "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: Git metadata should be excluded\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi

printf 'private path: /Us%s/example-user/project\n' 'ers' >"$SCRATCH/repo/private.txt"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: repository content leak should fail\n' >&2
	exit 1
fi

if ! grep -qF 'public-safety: denied pattern matched' "$SCRATCH/output"; then
	printf 'public-safety-test: failure should identify the denied pattern\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi

printf 'public-safety-test: ok\n'
