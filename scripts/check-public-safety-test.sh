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

rm -f "$SCRATCH/repo/private.txt"

# A tenant hostname is host-specific identity, which AGENTS.md bars from tracked
# files in this public repo. Assembled at runtime so this test file is not
# itself a match.
printf 'see acme-corp.%s for the board\n' 'atlassian.net' >"$SCRATCH/repo/tenant.md"
if "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: tenant hostname leak should fail\n' >&2
	exit 1
fi
rm -f "$SCRATCH/repo/tenant.md"

# Atlassian's own public API domain is not tenant identity and must not match,
# or every design doc citing the REST endpoint fails the gate.
printf 'call api.%s/ex/jira/{cloudId}/rest/api/3\n' 'atlassian.com' \
	>"$SCRATCH/repo/endpoint.md"
if ! "$CHECKER" "$SCRATCH/repo" >"$SCRATCH/output" 2>&1; then
	printf 'public-safety-test: public API domain should not be denied\n' >&2
	cat "$SCRATCH/output" >&2
	exit 1
fi
rm -f "$SCRATCH/repo/endpoint.md"

printf 'public-safety-test: ok\n'
