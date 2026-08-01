#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
helper="$script_dir/create-verified-issue.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/create-verified-issue-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

fail() {
	printf 'create-verified-issue-test: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local needle=$1 file=$2
	rg -F -- "$needle" "$file" >/dev/null || fail "missing '$needle' in $file"
}

assert_count() {
	local expected=$1 pattern=$2 file=$3 actual
	actual=$(rg -c -- "$pattern" "$file" || true)
	actual=${actual:-0}
	[[ $actual == "$expected" ]] ||
		fail "expected $expected matches for '$pattern' in $file, got $actual"
}

mkdir -p "$fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' >"$fixture/bin/gh"
cat >>"$fixture/bin/gh" <<'FAKE_GH'
set -euo pipefail
printf '%q ' "$@" >>"$GH_CALL_LOG"
printf '\n' >>"$GH_CALL_LOG"

if [[ $1 == issue && $2 == create ]]; then
  if [[ ${GH_SCENARIO:-success} == unresolved-create ]]; then
    printf 'created\n'
  else
    host=github.com
    [[ ${GH_SCENARIO:-success} == ghes ]] && host=ghe.example.com
    printf 'https://%s/example/repo/issues/%s\n' "$host" "${GH_ISSUE_NUMBER:-101}"
  fi
  exit 0
fi

if [[ $1 == issue && $2 == view ]]; then
  if [[ ${GH_SCENARIO:-success} == view-error ]]; then
    printf 'read failed\n' >&2
    exit 1
  fi
  case ${GH_SCENARIO:-success} in
    empty-body)
      body=''
      ;;
    missing-section | combined)
      body=$'## Problem\nP\n## Evidence\nE\n## Expected\nX'
      ;;
    malformed-json)
      printf '{bad json\n'
      exit 0
      ;;
    *)
      body=$'## Problem\nP\n## Evidence\nE\n## Expected\nX\n## Proposed approach\nA'
      ;;
  esac
  title='Confirmed title'
  labels='[{"name":"bug"},{"name":"status:ready"}]'
  parent='{"number":42}'
  case ${GH_SCENARIO:-success} in
    wrong-title | combined) title='Observed title' ;;
  esac
  case ${GH_SCENARIO:-success} in
    missing-label | combined) labels='[{"name":"bug"}]' ;;
    malformed-label) labels='["bad"]' ;;
  esac
  case ${GH_SCENARIO:-success} in
    wrong-parent | combined) parent='{"number":41}' ;;
    malformed-parent) parent='"bad"' ;;
  esac
  host=github.com
  [[ ${GH_SCENARIO:-success} == ghes ]] && host=ghe.example.com
  [[ ${GH_SCENARIO:-success} == wrong-host ]] && host=ghe.example.com
  response_number=${GH_ISSUE_NUMBER:-101}
  [[ ${GH_SCENARIO:-success} == wrong-number ]] && response_number=102
  response_repo=example/repo
  [[ ${GH_SCENARIO:-success} == wrong-url ]] && response_repo=other/repo
  jq -cn \
    --argjson number "$response_number" \
    --arg title "$title" \
    --arg body "$body" \
    --argjson labels "$labels" \
    --argjson parent "$parent" \
    --arg host "$host" \
    --arg response_repo "$response_repo" \
    '{number:$number,title:$title,body:$body,labels:$labels,parent:$parent,state:"OPEN",url:("https://"+$host+"/"+$response_repo+"/issues/"+($number|tostring))}'
  exit 0
fi

printf 'unexpected gh call: %s\n' "$*" >&2
exit 2
FAKE_GH
chmod +x "$fixture/bin/gh"

body_file="$fixture/body.md"
cat >"$body_file" <<'BODY'
## Problem
P
## Evidence
E
## Expected
X
## Proposed approach
A
BODY

run_case() {
	local scenario=$1
	: >"$fixture/calls"
	GH_SCENARIO=$scenario GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
		"$helper" --repo example/repo --title 'Confirmed title' --body-file "$body_file" \
		--label bug --label status:ready --parent 42 >"$fixture/stdout" 2>"$fixture/stderr"
}

run_ordinary_case() {
	local scenario=$1
	: >"$fixture/calls"
	GH_SCENARIO=$scenario GH_CALL_LOG="$fixture/calls" PATH="$fixture/bin:$PATH" \
		"$helper" --repo example/repo --title 'Confirmed title' --body-file "$body_file" \
		--label bug --label status:ready >"$fixture/stdout" 2>"$fixture/stderr"
}

if run_case success; then
	assert_contains 'https://github.com/example/repo/issues/101' "$fixture/stdout"
	assert_count 1 '^issue create ' "$fixture/calls"
	assert_count 1 '^issue view ' "$fixture/calls"
	assert_contains '--body-file' "$fixture/calls"
	[[ -s $body_file ]] || fail 'populated body file was not retained'
else
	fail 'success scenario failed'
fi

if run_case ghes; then
	assert_contains 'https://ghe.example.com/example/repo/issues/101' "$fixture/stdout"
else
	fail 'GHES scenario failed'
fi

for scenario in empty-body missing-section malformed-json wrong-title missing-label wrong-parent malformed-label malformed-parent; do
	if run_case "$scenario"; then
		fail "$scenario unexpectedly passed"
	fi
	assert_contains 'https://github.com/example/repo/issues/101' "$fixture/stderr"
	assert_count 1 '^issue create ' "$fixture/calls"
	assert_count 1 '^issue view ' "$fixture/calls"
done

if run_ordinary_case malformed-parent; then
	fail 'ordinary malformed parent unexpectedly passed'
fi
assert_contains 'https://github.com/example/repo/issues/101' "$fixture/stderr"
assert_contains 'malformed or incomplete JSON' "$fixture/stderr"

for scenario in wrong-host wrong-url wrong-number; do
	if run_case "$scenario"; then
		fail "$scenario unexpectedly passed"
	fi
	assert_contains 'https://github.com/example/repo/issues/101' "$fixture/stderr"
	assert_count 1 '^issue create ' "$fixture/calls"
	assert_count 1 '^issue view ' "$fixture/calls"
done
run_case wrong-host || true
assert_contains "url: expected 'https://github.com/example/repo/issues/101', observed 'https://ghe.example.com/example/repo/issues/101'" "$fixture/stderr"
run_case wrong-url || true
assert_contains "url: expected 'https://github.com/example/repo/issues/101', observed 'https://github.com/other/repo/issues/101'" "$fixture/stderr"
run_case wrong-number || true
assert_contains 'number: expected #101, observed #102' "$fixture/stderr"

if run_case combined; then
	fail 'combined mismatch unexpectedly passed'
fi
assert_contains "title: expected 'Confirmed title', observed 'Observed title'" "$fixture/stderr"
assert_contains "body: missing section 'Proposed approach'" "$fixture/stderr"
assert_contains "label: missing 'status:ready'" "$fixture/stderr"
assert_contains 'parent: expected #42, observed #41' "$fixture/stderr"

if run_case view-error; then
	fail 'view error unexpectedly passed'
fi
assert_contains 'https://github.com/example/repo/issues/101' "$fixture/stderr"
assert_contains 'read-back failed' "$fixture/stderr"
assert_count 1 '^issue create ' "$fixture/calls"
assert_count 1 '^issue view ' "$fixture/calls"

if run_case unresolved-create; then
	fail 'unresolved create unexpectedly passed'
fi
assert_contains 'durable issue URL could not be resolved' "$fixture/stderr"
assert_count 1 '^issue create ' "$fixture/calls"
assert_count 0 '^issue view ' "$fixture/calls"

if "$helper" --repo example/repo --title 'Confirmed title' --body-file "$fixture/missing" \
	>"$fixture/stdout" 2>"$fixture/stderr"; then
	fail 'missing body file unexpectedly passed'
fi
assert_contains 'body file must be a populated regular file' "$fixture/stderr"

skill_file="$script_dir/../SKILL.md"
assert_contains 'scripts/create-verified-issue.sh' "$skill_file"
assert_contains 'Retain the populated temporary body file' "$skill_file"
assert_contains 'verified URL is the only success result' "$skill_file"
assert_contains 'Do not retry, replace, or create a duplicate' "$skill_file"
if rg -n 'gh issue create --repo|gh issue create --parent' "$skill_file" >/dev/null; then
	fail 'SKILL.md retains a direct issue-create bypass'
fi

: >"$fixture/decompose-calls"
: >"$fixture/decompose-report"
for entry in '101:success' '102:wrong-title' '103:success'; do
	issue_number=${entry%%:*}
	scenario=${entry#*:}
	if ! GH_ISSUE_NUMBER=$issue_number GH_SCENARIO=$scenario \
		GH_CALL_LOG="$fixture/decompose-calls" PATH="$fixture/bin:$PATH" \
		"$helper" --repo example/repo --title 'Confirmed title' --body-file "$body_file" \
		--label bug --label status:ready --parent 42 >>"$fixture/decompose-report" 2>&1; then
		break
	fi
done
assert_count 2 '^issue create ' "$fixture/decompose-calls"
assert_contains 'https://github.com/example/repo/issues/102' "$fixture/decompose-report"
assert_contains "title: expected 'Confirmed title', observed 'Observed title'" "$fixture/decompose-report"

printf 'create-verified-issue-test: ok\n'
