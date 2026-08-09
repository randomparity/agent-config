#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
DETECTOR="$ROOT/content/skills/preflight/scripts/detect-host-architecture"
RESOLVER="$ROOT/content/skills/preflight/scripts/resolve-architecture-context"
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

assert_contains() {
	local file="$1" expected="$2"
	rg -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
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
run_case tab output $'riscv\t64' 0 2 $'unsupported\triscv\\t64' \
	"detect-host-architecture: unsupported machine 'riscv\\t64'; supported: x86_64, arm64, ppc64le, s390x"
run_case newline output $'riscv\n64' 0 2 $'unsupported\triscv\\n64' \
	"detect-host-architecture: unsupported machine 'riscv\\n64'; supported: x86_64, arm64, ppc64le, s390x"
run_case uname-failure fail '' 42 3 $'detection-failed\tuname-exit-42' \
	'detect-host-architecture: uname -m failed with exit 42; retry after fixing uname'
run_missing_uname

assert_context() {
	local expected="$1"
	shift
	local actual
	actual="$("$RESOLVER" "$@")"
	[[ "$actual" == "$expected" ]] ||
		fail "context $*: expected '$expected', got '$actual'"
}

[[ -x "$RESOLVER" ]] || fail "missing executable resolver: $RESOLVER"
assert_context $'HOST_ARCHITECTURE\tx86_64\nARCHITECTURE_RELATIONSHIP\tincluded' \
	ok x86_64 declared amd64 arm64
assert_context $'HOST_ARCHITECTURE\tarm64\nARCHITECTURE_RELATIONSHIP\tdifferent' \
	ok arm64 declared x86_64 ppc64le
assert_context $'HOST_ARCHITECTURE\tx86_64\nARCHITECTURE_RELATIONSHIP\tno-target-declared' \
	ok x86_64 none
assert_context $'HOST_ARCHITECTURE\tunsupported (riscv64)\nARCHITECTURE_RELATIONSHIP\thost-unresolved' \
	unsupported riscv64 declared riscv64
assert_context $'HOST_ARCHITECTURE\tdetection failed (uname-exit-42)\nARCHITECTURE_RELATIONSHIP\thost-unresolved' \
	detection-failed uname-exit-42 declared x86_64
assert_context $'HOST_ARCHITECTURE\tdetection failed (uname-missing)\nARCHITECTURE_RELATIONSHIP\tunresolved-target-conflict' \
	detection-failed uname-missing conflict x86_64 arm64

resolver_error="$FIXTURE/resolver-error"
resolver_status=0
"$RESOLVER" ok $'x86_64\nspoofed' declared x86_64 \
	>"$resolver_error.stdout" 2>"$resolver_error.stderr" || resolver_status=$?
[[ "$resolver_status" -eq 64 ]] || fail "resolver malformed input: got exit $resolver_status"
assert_file '' "$resolver_error.stdout" 'resolver malformed input stdout'
assert_file 'resolve-architecture-context: host value must be one escaped record field' \
	"$resolver_error.stderr" 'resolver malformed input stderr'

mutated_resolver="$FIXTURE/mutated-resolver"
cp "$RESOLVER" "$mutated_resolver"
sed -i.bak 's/relationship=included/relationship=different/' "$mutated_resolver"
chmod +x "$mutated_resolver"
mutated_output="$("$mutated_resolver" ok x86_64 declared amd64 arm64)"
if [[ "$mutated_output" == *$'ARCHITECTURE_RELATIONSHIP\tincluded'* ]]; then
	fail 'relationship mutation unexpectedly preserved the included result'
fi

preflight="$ROOT/content/skills/preflight/SKILL.md"
# shellcheck disable=SC2016 # these backticks are literal Markdown code spans;
# expanding them would execute the contract values instead of checking the skill text.
for expected in \
	'`HOST_ARCHITECTURE`' \
	'`TARGET_ARCHITECTURES`' \
	'`ARCHITECTURE_RELATIONSHIP`' \
	'native applicable-instruction precedence' \
	'every effective target declaration' \
	'`unresolved-target-conflict`' \
	'`host-unresolved`' \
	'`no-target-declared`' \
	'`included`' \
	'`different`' \
	'| 1 | Effective target declarations contradict | `unresolved-target-conflict` |' \
	'| 2 | Host is unsupported or detection failed | `host-unresolved` |' \
	'| 3 | No effective target is declared | `no-target-declared` |' \
	'| 4 | Host is in the effective target set | `included` |' \
	'| 5 | Host is not in the effective target set | `different` |' \
	'Architecture-insensitive work may continue' \
	'Cross-compilation, emulation, and multi-architecture CI are outside'; do
	assert_contains "$preflight" "$expected"
done

projection_files=(
	"$ROOT/content/instructions/global-development-standards.md"
	"$ROOT/agents/claude/shared/CLAUDE.md"
	"$ROOT/agents/codex/shared/AGENTS.md"
	"$ROOT/agents/bob/shared/AGENTS.md"
	"$ROOT/agents/bob/shared/rules/global-development-standards.md"
)
for projection in "${projection_files[@]}"; do
	assert_contains "$projection" \
		'Host architecture and project target architectures are separate facts.'
	assert_contains "$projection" \
		'Applicable project-local instructions and policy are authoritative for target architectures.'
	assert_contains "$projection" 'architecture-sensitive generation, build, or verification'
	assert_contains "$projection" 'preflight'
	assert_contains "$projection" 'retain'
	rg -Fiq -- 'never infer' "$projection" ||
		fail "$projection does not prohibit target inference"
done

mutated_projection="$FIXTURE/mutated-projection.md"
cp "${projection_files[0]}" "$mutated_projection"
sed -i.bak '/[Nn]ever infer/d' "$mutated_projection"
if rg -Fiq -- 'never infer' "$mutated_projection"; then
	fail 'projection contract mutation unexpectedly passed'
fi

printf 'architecture-awareness-test: all assertions passed\n'
