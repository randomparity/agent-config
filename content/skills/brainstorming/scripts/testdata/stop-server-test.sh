#!/usr/bin/env bash
# Regression tests for authenticated brainstorm shutdown.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$(dirname "$SCRIPT_DIR")/stop-server.sh"
START_SCRIPT="$(dirname "$SCRIPT_DIR")/start-server.sh"

passed=0
failed=0
fixture=""
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
  if [ -n "$fixture" ] && [ -d "$fixture" ]; then
    rm -R "$fixture"
  fi
  fixture=""
}
trap cleanup EXIT

pass() {
  passed=$((passed + 1))
  printf '  ok   %s\n' "$1"
}

fail() {
  failed=$((failed + 1))
  printf '  FAIL %s (%s)\n' "$1" "$2"
}

write_record() {
  local record=$1 session=$2 pid=$3 server_id=$4 port=${5:-49152}
  {
    printf '{"version":1,"pid":%s,"server_id":"%s","session_dir":"%s",' \
      "$pid" "$server_id" "$session"
    printf '"project_key":null,"control_port":%s,"control_token":"%s"}\n' \
      "$port" "$(printf 'b%.0s' {1..64})"
  } >"$record"
  chmod 600 "$record"
}

run_authenticated_stop() {
  local name='authenticated metadata stops the server'
  local home output second session got=0
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  home="$fixture/home"
  mkdir -p "$home"

  HOME="$home" "$START_SCRIPT" --background >"$fixture/start.json"
  session="$(node -e '
    const fs = require("fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(value.state_dir.replace(/\/state$/, ""));
  ' "$fixture/start.json")"
  server_pid="$(node -e '
    const fs = require("fs");
    process.stdout.write(String(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).pid));
  ' "$session/state/server-control.json")"

  output="$(HOME="$home" "$SCRIPT" "$session")" || got=$?
  for _ in {1..30}; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  second="$(HOME="$home" "$SCRIPT" "$session")"
  if [ "$got" -eq 0 ] && [[ "$output" == *'"status":"stopped"'* ]] &&
    ! kill -0 "$server_pid" 2>/dev/null && [ ! -e "$session" ] &&
    [[ "$second" == *'"status":"not_running"'* ]]; then
    pass "$name"
  else
    fail "$name" "exit=$got output=$output pid=$server_pid"
  fi
  server_pid=""
  cleanup
}

run_missing_twice() {
  local name='a missing session is idempotent not_running'
  local session first second
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  session="$fixture/gone"
  first="$("$SCRIPT" "$session")"
  second="$("$SCRIPT" "$session")"
  if [[ "$first" == *'"status":"not_running"'* ]] && [ "$first" = "$second" ]; then
    pass "$name"
  else
    fail "$name" "first=$first second=$second"
  fi
  cleanup
}

run_malformed_preserved() {
  local name='malformed present metadata fails closed and survives'
  local session record output got=0
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  session="$fixture/session"
  record="$session/state/server-control.json"
  mkdir -p "$session/state"
  printf '{broken\n' >"$record"
  chmod 600 "$record"
  output="$("$SCRIPT" "$session")" || got=$?
  if [ "$got" -ne 0 ] && [[ "$output" == *'"status":"failed"'* ]] && [ -f "$record" ]; then
    pass "$name"
  else
    fail "$name" "exit=$got output=$output record_exists=$([ -f "$record" ] && echo yes || echo no)"
  fi
  cleanup
}

run_marker_failure_exits_and_preserves() {
  local name='stopped-marker failure exits and preserves metadata for stale cleanup'
  local home output record record_exists second session state got=0 second_got=0
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  home="$fixture/home"
  mkdir -p "$home"

  HOME="$home" "$START_SCRIPT" --background >"$fixture/start.json"
  session="$(node -e '
    const fs = require("fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(value.state_dir.replace(/\/state$/, ""));
  ' "$fixture/start.json")"
  state="$session/state"
  record="$state/server-control.json"
  server_pid="$(node -e '
    const fs = require("fs");
    process.stdout.write(String(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).pid));
  ' "$record")"

  mkdir "$state/server-stopped"
  output="$(HOME="$home" "$SCRIPT" "$session")" || got=$?
  for _ in {1..30}; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  rmdir "$state/server-stopped"
  if [ "$got" -ne 0 ] && [[ "$output" == *'"status":"failed"'* ]] &&
    ! kill -0 "$server_pid" 2>/dev/null && [ -f "$record" ]; then
    second="$(HOME="$home" "$SCRIPT" "$session")" || second_got=$?
    if [ "$second_got" -eq 0 ] && [[ "$second" == *'"status":"stale_pid"'* ]] &&
      [ ! -e "$record" ]; then
      pass "$name"
    else
      record_exists=$([ -f "$record" ] && echo yes || echo no)
      fail "$name" \
        "second_exit=$second_got second=$second record_exists=$record_exists"
    fi
  else
    record_exists=$([ -f "$record" ] && echo yes || echo no)
    fail "$name" \
      "exit=$got output=$output pid=$server_pid record_exists=$record_exists"
  fi
  server_pid=""
  cleanup
}

run_confirmed_dead_cleanup() {
  local name='confirmed-dead metadata is cleaned as stale_pid'
  local session record output got=0
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  session="$fixture/session"
  record="$session/state/server-control.json"
  mkdir -p "$session/state"
  write_record "$record" "$session" 2147483647 "$(printf 'a%.0s' {1..32})"
  output="$("$SCRIPT" "$session")" || got=$?
  if [ "$got" -eq 0 ] && [[ "$output" == *'"status":"stale_pid"'* ]] &&
    [ ! -e "$record" ]; then
    pass "$name"
  else
    fail "$name" "exit=$got output=$output record_exists=$([ -e "$record" ] && echo yes || echo no)"
  fi
  cleanup
}

run_indeterminate_live_preserved() {
  local name='live refused metadata without boundary proof fails closed'
  local session record output got=0
  if [ -r /proc/self/cmdline ]; then
    printf '  skip %s: Linux provides exact unrelated-process proof\n' "$name"
    return
  fi
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  session="$fixture/session"
  record="$session/state/server-control.json"
  mkdir -p "$session/state"
  write_record "$record" "$session" $$ "$(printf 'c%.0s' {1..32})"
  output="$("$SCRIPT" "$session")" || got=$?
  if [ "$got" -ne 0 ] && [[ "$output" == *'"status":"failed"'* ]] &&
    [ -f "$record" ] && kill -0 $$ 2>/dev/null; then
    pass "$name"
  else
    fail "$name" "exit=$got output=$output record_exists=$([ -f "$record" ] && echo yes || echo no)"
  fi
  cleanup
}

run_loose_mode_preserved() {
  local name='group-readable recovery metadata fails closed and survives'
  local session record output got=0
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  session="$fixture/session"
  record="$session/state/server-control.json"
  mkdir -p "$session/state"
  write_record "$record" "$session" $$ "$(printf 'd%.0s' {1..32})"
  chmod 640 "$record"
  output="$("$SCRIPT" "$session")" || got=$?
  if [ "$got" -ne 0 ] && [[ "$output" == *'"status":"failed"'* ]] && [ -f "$record" ]; then
    pass "$name"
  else
    fail "$name" "exit=$got output=$output"
  fi
  cleanup
}

run_no_stop_signal_path() {
  local name='explicit stop contains no PID signalling or flat argv path'
  if rg -n '(^|[;&|[:space:]])(kill|ps)([[:space:]]|$)' "$SCRIPT"; then
    fail "$name" 'found a shell process signalling or inspection command'
  else
    pass "$name"
  fi
}

run_proven_unrelated() {
  local name='exact Linux argv proof preserves an unrelated process'
  local session record output got=0
  if [ ! -r /proc/self/cmdline ]; then
    printf '  skip %s: /proc argv boundaries unavailable\n' "$name"
    return
  fi
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-stop-test.XXXXXX")"
  session="$fixture/session"
  record="$session/state/server-control.json"
  mkdir -p "$session/state"
  sleep 300 &
  server_pid=$!
  write_record "$record" "$session" "$server_pid" "$(printf 'a%.0s' {1..32})"
  output="$("$SCRIPT" "$session")" || got=$?
  if [ "$got" -eq 0 ] && [[ "$output" == *'"status":"stale_pid"'* ]] &&
    kill -0 "$server_pid" 2>/dev/null && [ ! -e "$record" ]; then
    pass "$name"
  else
    fail "$name" "exit=$got output=$output"
  fi
  cleanup
}

main() {
  printf 'stop-server.sh\n\n'
  run_authenticated_stop
  run_missing_twice
  run_malformed_preserved
  run_marker_failure_exits_and_preserves
  run_confirmed_dead_cleanup
  run_indeterminate_live_preserved
  run_loose_mode_preserved
  run_proven_unrelated
  run_no_stop_signal_path
  printf '\n%d passed, %d failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
}

main "$@"
