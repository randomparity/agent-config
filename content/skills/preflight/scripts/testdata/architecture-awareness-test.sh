#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
DETECTOR="$ROOT/content/skills/preflight/scripts/detect-host-architecture"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/architecture-awareness-test.XXXXXX")"

cleanup() {
	rm -R "$FIXTURE"
}
trap cleanup EXIT

fail() {
	printf 'architecture-awareness-test: %s\n' "$1" >&2
	exit 1
}

assert_file() {
	local expected="$1" actual_file="$2" label="$3" actual
	actual="$(cat "$actual_file")"
	[[ "$actual" == "$expected" ]] ||
		fail "$label: expected '$expected', got '$actual'"
}

make_fake_uname() {
	local bin_dir="$1"
	mkdir -p "$bin_dir"
	cat >"$bin_dir/uname" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${FAKE_UNAME_MODE:-output}" in
output) printf '%s\n' "${FAKE_UNAME_VALUE-}" ;;
fail)
	printf '%s\n' 'raw uname failure sentinel' >&2
	exit "${FAKE_UNAME_STATUS:-42}"
	;;
*) exit 99 ;;
esac
EOF
	chmod +x "$bin_dir/uname"
}

run_case() {
	local name="$1" mode="$2" value="$3" fake_status="$4"
	local expected_status="$5" expected_stdout="$6" expected_stderr="$7"
	local case_dir="$FIXTURE/$name" status=0
	local bin_dir="$case_dir/bin"
	mkdir -p "$case_dir"
	make_fake_uname "$bin_dir"

	PATH="$bin_dir" FAKE_UNAME_MODE="$mode" FAKE_UNAME_VALUE="$value" \
		FAKE_UNAME_STATUS="$fake_status" /bin/bash "$DETECTOR" \
		>"$case_dir/stdout" 2>"$case_dir/stderr" || status=$?

	[[ "$status" -eq "$expected_status" ]] ||
		fail "$name: expected exit $expected_status, got $status"
	assert_file "$expected_stdout" "$case_dir/stdout" "$name stdout"
	assert_file "$expected_stderr" "$case_dir/stderr" "$name stderr"
	printf '  ok   %s\n' "$name"
}

run_missing_uname() {
	local case_dir="$FIXTURE/missing-uname" status=0
	mkdir -p "$case_dir/bin"
	PATH="$case_dir/bin" /bin/bash "$DETECTOR" \
		>"$case_dir/stdout" 2>"$case_dir/stderr" || status=$?
	[[ "$status" -eq 3 ]] || fail "missing uname: expected exit 3, got $status"
	assert_file $'detection-failed\tuname-missing' "$case_dir/stdout" \
		'missing uname stdout'
	assert_file \
		'detect-host-architecture: uname is required; install or expose uname in PATH' \
		"$case_dir/stderr" 'missing uname stderr'
	printf '  ok   missing uname\n'
}

[[ -x "$DETECTOR" ]] || fail "missing executable detector: $DETECTOR"

run_case x86_64 output x86_64 0 0 $'ok\tx86_64' ''
run_case amd64 output amd64 0 0 $'ok\tx86_64' ''
run_case arm64 output arm64 0 0 $'ok\tarm64' ''
run_case aarch64 output aarch64 0 0 $'ok\tarm64' ''
run_case ppc64le output ppc64le 0 0 $'ok\tppc64le' ''
run_case s390x output s390x 0 0 $'ok\ts390x' ''
run_case unsupported output riscv64 0 2 $'unsupported\triscv64' \
	"detect-host-architecture: unsupported machine 'riscv64'; supported: x86_64, arm64, ppc64le, s390x"
run_case empty output '' 0 2 $'unsupported\t<empty>' \
	"detect-host-architecture: unsupported machine '<empty>'; supported: x86_64, arm64, ppc64le, s390x"
run_case uname-failure fail '' 42 3 $'detection-failed\tuname-exit-42' \
	'detect-host-architecture: uname -m failed with exit 42; retry after fixing uname'
run_missing_uname

printf 'architecture-awareness-test: all assertions passed\n'
