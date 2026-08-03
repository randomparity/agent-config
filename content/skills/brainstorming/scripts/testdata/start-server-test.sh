#!/usr/bin/env bash
# Regression tests for start-server.sh argument validation.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The suite lives in `testdata/` so it is excluded from the installed payload
# (ADR 0025); the script it exercises ships, and sits one level up.
SCRIPT="$(dirname "$SCRIPT_DIR")/start-server.sh"

passed=0
failed=0

run_case() {
  local name=$1 expected=$2 want=$3
  shift 3
  local dir got=0
  # Allocated, not constructed: `just test` and CI now run this suite, and a
  # name derived from the pid plus two counters is predictable enough for a
  # local actor to pre-create as a symlink, redirecting the writes below.
  dir="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-start-test.XXXXXX")"

  if "$SCRIPT" "$@" >"$dir/out" 2>"$dir/err"; then
    got=0
  else
    got=$?
  fi

  if [ "$got" = "$expected" ] && grep -qF -- "$want" "$dir/out" "$dir/err"; then
    passed=$((passed + 1))
    printf '  ok   %s\n' "$name"
  else
    failed=$((failed + 1))
    printf '  FAIL %s (exit=%s, expected=%s, wanted=%s)\n' \
      "$name" "$got" "$expected" "$want"
    sed -n '1,8p' "$dir/out" "$dir/err"
  fi

  if [ -d "$dir" ]; then
    rm -R "$dir"
  fi
}

main() {
  printf 'start-server.sh\n\n'
  run_case "missing --host value" 1 "--host requires a value" --host
  run_case "next flag is not a --host value" 1 "--host requires a value" \
    --host --url-host localhost
  run_case "missing --project-dir value" 1 "--project-dir requires a value" \
    --project-dir
  run_case "missing --url-host value" 1 "--url-host requires a value" --url-host
  run_case "zero idle timeout rejected" 1 "must be a positive integer" \
    --idle-timeout-minutes 0
  run_case "unknown flag rejected" 1 "Unknown argument: --bogus" --bogus

  printf '\n%d passed, %d failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
}

main "$@"
