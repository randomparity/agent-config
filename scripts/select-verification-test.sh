#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r variable; do
	[[ -n $variable ]] && unset "$variable"
done < <(git rev-parse --local-env-vars)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$ROOT/scripts/select-verification.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/select-verification-test.XXXXXX")"
REPO="$SCRATCH/repo"
BIN="$SCRATCH/bin"
LOG="$SCRATCH/just.log"
OUTPUT="$SCRATCH/output"
GIT_BINARY="$(command -v git)"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/select-verification-test.*) rm -R "$SCRATCH" ;;
	*) printf 'select-verification-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

if [[ ! -x "$SELECTOR" ]]; then
	printf 'select-verification-test: selector does not exist: %s\n' "$SELECTOR" >&2
	exit 127
fi

mkdir -p "$BIN"
cat >"$BIN/just" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$JUST_LOG"
if [[ ${1:-} == "${FAIL_RECIPE:-}" ]]; then
	exit 73
fi
EOF
chmod +x "$BIN/just"

assert_hook_env_isolation() {
	local hook_repo hook_index child_status
	hook_repo="$SCRATCH/hook-repository"
	mkdir -p "$hook_repo"
	git -C "$hook_repo" init --quiet
	git -C "$hook_repo" config user.email hook@example.test
	git -C "$hook_repo" config user.name Hook
	printf 'hook\n' >"$hook_repo/README.md"
	git -C "$hook_repo" add README.md
	git -C "$hook_repo" commit --quiet -m hook
	hook_index="$(git -C "$hook_repo" rev-parse --absolute-git-dir)/index"
	git -C "$hook_repo" ls-files --stage >"$SCRATCH/hook-index-before"
	set +e
	GIT_INDEX_FILE="$hook_index" SELECTOR_TEST_HOOK_CHILD=1 "$0" >"$SCRATCH/hook-output" 2>&1
	child_status=$?
	set -e
	if [[ $child_status -ne 0 ]]; then
		printf 'not ok - selector fixture should run under hook-local Git state\n' >&2
		sed -n '1,80p' "$SCRATCH/hook-output" >&2
		exit 1
	fi
	git -C "$hook_repo" ls-files --stage >"$SCRATCH/hook-index-after"
	if ! cmp -s "$SCRATCH/hook-index-before" "$SCRATCH/hook-index-after"; then
		printf 'not ok - selector fixture changed hook-local index\n' >&2
		diff -u "$SCRATCH/hook-index-before" "$SCRATCH/hook-index-after" >&2 || :
		exit 1
	fi
}

if [[ ${SELECTOR_TEST_HOOK_CHILD:-} != 1 ]]; then
	assert_hook_env_isolation
fi

new_repo() {
	rm -R "$REPO" 2>/dev/null || :
	mkdir -p "$REPO"
	git -C "$REPO" init --quiet
	git -C "$REPO" config user.email selector@example.test
	git -C "$REPO" config user.name Selector
	printf 'base\n' >"$REPO/base.txt"
	git -C "$REPO" add base.txt
	git -C "$REPO" commit --quiet -m base
	: >"$LOG"
}

stage_file() {
	local path=$1 content=${2:-content}
	mkdir -p "$(dirname "$REPO/$path")"
	printf '%s\n' "$content" >"$REPO/$path"
	git -C "$REPO" add -- "$path"
}

run_selector() {
	: >"$OUTPUT"
	(
		cd "$REPO"
		PATH="$BIN:$PATH" JUST_LOG="$LOG" "$SELECTOR"
	) >"$OUTPUT" 2>&1
}

assert_recipes() {
	local name=$1 expected=$2
	if ! diff -u <(printf '%s' "$expected") "$LOG"; then
		printf 'not ok - %s selected unexpected recipes\n' "$name" >&2
		exit 1
	fi
}

assert_output() {
	local name=$1
	if ! rg -q '^verification selection:' "$OUTPUT" ||
		! rg -q '^verification elapsed seconds:' "$OUTPUT"; then
		printf 'not ok - %s should print selection and elapsed-time labels\n' "$name" >&2
		cat "$OUTPUT" >&2
		exit 1
	fi
}

assert_deferred() {
	local name=$1 expected=${2:-}
	assert_recipes "$name" "$expected"
	if ! rg -qx 'verification deferred: unclassified paths will run on push/CI' "$OUTPUT"; then
		printf 'not ok - %s should report deferred paths\n' "$name" >&2
		cat "$OUTPUT" >&2
		exit 1
	fi
}

assert_selects() {
	local name=$1 expected=$2
	run_selector
	assert_recipes "$name" "$expected"
	assert_output "$name"
}

new_repo
stage_file docs/superpowers/specs/example.md
assert_selects 'direct spec file' $'public-safety\nreferences-check\n'

new_repo
stage_file Justfile
run_selector
assert_deferred 'Justfile is deferred'

new_repo
stage_file docs/superpowers/plans/example.md
assert_selects 'direct plan file' $'public-safety\nreferences-check\n'

new_repo
stage_file docs/adr/0042-example.md
assert_selects 'direct ADR file' $'records\npublic-safety\nreferences-check\n'

new_repo
stage_file docs/debt/0042-example.md
assert_selects 'direct debt file' $'records\npublic-safety\nreferences-check\n'

new_repo
stage_file scripts/check-public-safety.sh
assert_selects 'public-safety checker' \
	$'lint\nformat-check\ntest-public-safety\nsuites-check\npublic-safety\n'

new_repo
stage_file scripts/check-public-safety-test.sh
assert_selects 'public-safety checker test' $'lint\nformat-check\ntest-public-safety\nsuites-check\n'

new_repo
stage_file docs/superpowers/specs/nested/example.md
assert_selects 'nested spec file' $'public-safety\nreferences-check\n'

new_repo
stage_file docs/guides/nested/example.md
assert_selects 'nested prose file' $'public-safety\nreferences-check\n'

new_repo
stage_file docs/superpowers/specs/example.txt
run_selector
assert_deferred 'non-Markdown spec child is deferred'

new_repo
stage_file docs/adr/nested/example.md
assert_selects 'nested ADR file' $'records\npublic-safety\nreferences-check\n'

new_repo
stage_file docs/debt/nested/example.md
assert_selects 'nested debt file' $'records\npublic-safety\nreferences-check\n'

new_repo
stage_file unknown.txt
run_selector
assert_deferred 'unknown path is deferred'

new_repo
stage_file .github/workflows/verify.yml
run_selector
assert_deferred 'workflow is deferred'

new_repo
stage_file content/instructions/global-development-standards.md
run_selector
assert_deferred 'shared contract is deferred'

new_repo
stage_file docs/superpowers/specs/first.md
stage_file docs/superpowers/plans/second.md
assert_selects 'duplicate recipes run once' $'public-safety\nreferences-check\n'

new_repo
stage_file docs/superpowers/specs/focused.md
stage_file Justfile
run_selector
assert_recipes 'mixed focused and deferred paths' $'public-safety\nreferences-check\n'
assert_output 'mixed focused and deferred paths'
assert_deferred 'mixed focused and deferred paths' $'public-safety\nreferences-check\n'

new_repo
stage_file deleted-unknown.txt
git -C "$REPO" commit --quiet -m tracked
git -C "$REPO" rm --quiet deleted-unknown.txt
run_selector
assert_deferred 'deleted unknown path is deferred'

new_repo
stage_file docs/superpowers/specs/renamed.md
git -C "$REPO" commit --quiet -m tracked
git -C "$REPO" mv docs/superpowers/specs/renamed.md renamed.txt
run_selector
assert_recipes 'rename old focused endpoint' $'public-safety\nreferences-check\n'
assert_deferred 'rename old focused endpoint' $'public-safety\nreferences-check\n'

new_repo
stage_file renamed.txt
git -C "$REPO" commit --quiet -m tracked
mkdir -p "$REPO/docs/superpowers/specs"
git -C "$REPO" mv renamed.txt docs/superpowers/specs/renamed.md
assert_selects 'rename new focused endpoint' $'public-safety\nreferences-check\n'

new_repo
for number in $(seq 1 150); do
	stage_file "docs/superpowers/specs/$number.md"
done
assert_selects 'large staged set' $'public-safety\nreferences-check\n'

new_repo
sentinel="$REPO/not-executed"
# shellcheck disable=SC2016 # Literal Git pathname must contain unexpanded shell syntax.
metachar_path='odd $(touch not-executed); $HOME; [x].md'
stage_file "$metachar_path"
run_selector
assert_deferred 'metacharacter path is deferred'
if [[ -e "$sentinel" ]] || rg -Fq "$metachar_path" "$OUTPUT"; then
	printf 'not ok - metacharacter path must not execute or enter output\n' >&2
	exit 1
fi

new_repo
run_selector
assert_recipes 'empty index' ''
if ! rg -q '^verification selection: no staged paths$' "$OUTPUT"; then
	printf 'not ok - empty index should be a no-op\n' >&2
	cat "$OUTPUT" >&2
	exit 1
fi

new_repo
stage_file docs/superpowers/specs/failure.md
set +e
(
	cd "$REPO"
	PATH="$BIN:$PATH" JUST_LOG="$LOG" FAIL_RECIPE=public-safety "$SELECTOR"
) >"$OUTPUT" 2>&1
status=$?
set -e
if [[ $status -ne 73 ]]; then
	printf 'not ok - focused recipe failure should propagate, got %s\n' "$status" >&2
	exit 1
fi
assert_recipes 'focused failure stops later recipes' $'public-safety\n'

new_repo
stage_file docs/superpowers/specs/enumeration.md
mkdir -p "$SCRATCH/failing-git"
cat >"$SCRATCH/failing-git/git" <<EOF
#!/usr/bin/env bash
if [[ \${1:-} == diff ]]; then
  exit 88
fi
exec "$GIT_BINARY" "\$@"
EOF
chmod +x "$SCRATCH/failing-git/git"
set +e
(
	cd "$REPO"
	PATH="$SCRATCH/failing-git:$BIN:$PATH" JUST_LOG="$LOG" "$SELECTOR"
) >"$OUTPUT" 2>&1
status=$?
set -e
if [[ $status -eq 0 ]] || ! rg -q 'could not read staged paths' "$OUTPUT"; then
	printf 'not ok - Git enumeration failure should be actionable and nonzero\n' >&2
	cat "$OUTPUT" >&2
	exit 1
fi

new_repo
stage_file scripts/check-public-safety-test.sh
stage_file docs/adr/0042-order.md
assert_selects 'stable path order' \
	$'records\npublic-safety\nreferences-check\nlint\nformat-check\ntest-public-safety\nsuites-check\n'

printf 'select-verification-test: ok\n'
