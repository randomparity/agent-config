#!/usr/bin/env bash
set -euo pipefail

# Stop a brainstorm server through its authenticated, session-local control record.
# Usage: stop-server.sh <session_dir>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -ne 1 || -z "${1-}" ]]; then
  echo '{"error": "Usage: stop-server.sh <session_dir>"}'
  exit 1
fi

SESSION_DIR=$1
if [[ ! -e "$SESSION_DIR" && ! -L "$SESSION_DIR" ]]; then
  echo '{"status":"not_running"}'
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo '{"status":"failed","error":"node not found on PATH; cannot stop brainstorm server"}'
  exit 1
fi

marked=""
if ! marked="$(cd -P -- "$SESSION_DIR" 2>/dev/null && printf '%s_' "$PWD")"; then
  printf '{"status":"failed","error":"cannot canonicalize supplied brainstorm session path"}\n'
  exit 1
fi
SESSION_DIR=${marked%_}

printf '%s' "$SESSION_DIR" | node "$SCRIPT_DIR/server-control.cjs" stop-session
