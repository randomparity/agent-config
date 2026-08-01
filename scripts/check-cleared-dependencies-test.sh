#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tracking=$repo_root/content/skills/github-tracking/SKILL.md

fail() {
	printf 'cleared-dependencies-test: %s\n' "$*" >&2
	exit 1
}

assert_text() {
	local file=$1 text=$2
	rg -q --fixed-strings "$text" "$file" || fail "$file missing: $text"
}

extract_recipe() {
	local output=$1
	awk '
    $0 == "# BEGIN CLEARED-DEPENDENCY RECIPE" { copy = 1; next }
    $0 == "# END CLEARED-DEPENDENCY RECIPE" { copy = 0; found = 1 }
    copy { print }
    END { if (!found) exit 42 }
  ' "$tracking" >"$output"
}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
recipe=$tmp_dir/recipe.sh
extract_recipe "$recipe" || fail 'canonical executable recipe is missing'
shellcheck "$recipe"
shfmt -d -i 2 "$recipe"
# shellcheck source=/dev/null
source "$recipe"

gh_log=$tmp_dir/gh.log
ready_state=$tmp_dir/ready
fake_mode=normal

gh() {
	if [[ $1 == api ]]; then
		printf '%s\n' '[[{"number":101,"state":"open","body":"Blocked by #1","labels":[{"name":"status:blocked"},{"name":"status:in-progress"}]},{"number":102,"state":"open","body":"Blocked by #1\nBlocked by #2","labels":[{"name":"status:blocked"}]},{"number":103,"state":"open","body":"Blocked by #abc","labels":[{"name":"status:blocked"}]},{"number":104,"state":"open","body":"Blocked by #1","labels":[{"name":"status:blocked"},{"name":"epic"}]}],[{"number":106,"state":"open","body":"Blocked by #1","labels":[{"name":"status:blocked"}]}]]'
		return
	fi
	if [[ $1 == label && $2 == create ]]; then
		[[ $* == *'--repo owner/repo'* ]] || fail 'label create omitted the target repo'
		return
	fi
	if [[ $1 == issue && $2 == edit ]]; then
		printf '%s\n' "$*" >>"$gh_log"
		: >"$ready_state"
		return
	fi
	if [[ $1 == issue && $2 == view ]]; then
		case $3 in
		1) printf 'CLOSED\n' ;;
		2) printf 'OPEN\n' ;;
		404)
			printf 'not found\n' >&2
			return 1
			;;
		500)
			printf 'permission denied\n' >&2
			return 1
			;;
		101)
			if [[ $* == *'--json labels'* ]]; then
				if [[ $fake_mode == conflict ]]; then
					printf '%s\n' '{"labels":[{"name":"status:ready"},{"name":"status:blocked"}]}'
				else
					printf '%s\n' '{"labels":[{"name":"status:ready"}]}'
				fi
			elif [[ $fake_mode == stale ]]; then
				printf '%s\n' '{"number":101,"state":"OPEN","body":"Blocked by #1","labels":[{"name":"status:ready"}]}'
			elif [[ $fake_mode == changed-body ]]; then
				printf '%s\n' '{"number":101,"state":"OPEN","body":"Blocked by #2","labels":[{"name":"status:blocked"},{"name":"status:in-progress"}]}'
			else
				printf '%s\n' '{"number":101,"state":"OPEN","body":"Blocked by #1","labels":[{"name":"status:blocked"},{"name":"status:in-progress"}]}'
			fi
			;;
		*) fail "unexpected fake gh call: $*" ;;
		esac
		return
	fi
	fail "unexpected fake gh call: $*"
}

cleared_dependency_body_verdict owner/repo 10 $'Blocked by #1\nBlocked by #1' ||
	fail 'multiple closed canonical blockers should clear'
if cleared_dependency_body_verdict owner/repo 10 $'Blocked by #1\nBlocked by #2'; then
	fail 'an open blocker must retain the dependent'
fi
# Assigned by the sourced canonical recipe.
# shellcheck disable=SC2154
[[ $cleared_dependency_reason == 'open blocker #2 retains #10' ]] ||
	fail 'open-blocker report is not actionable'
for fixture in 'Blocked by #404' 'Blocked by #500' 'Blocked by #abc' ' Blocked by #1'; do
	if cleared_dependency_body_verdict owner/repo 10 "$fixture"; then
		fail "invalid dependency record cleared: $fixture"
	fi
done

plan_errors=$tmp_dir/plan-errors
set +e
plan_output=$(reconcile_cleared_dependencies plan owner/repo 2>"$plan_errors")
plan_status=$?
set -e
[[ $plan_status -eq 1 ]] || fail 'degraded dependents must produce partial-failure status'
[[ $plan_output == $'ready #101\nready #106' ]] ||
	fail "plan mode selected the wrong dependents: $plan_output"
[[ ! -s $gh_log ]] || fail 'plan mode wrote labels'
rg -q 'open blocker #2 retains #102' "$plan_errors" || fail 'open blocker was not reported'
rg -q 'malformed reference on #103' "$plan_errors" || fail 'malformed line was not reported'

initial='{"number":101,"state":"OPEN","body":"Blocked by #1","labels":[{"name":"status:blocked"},{"name":"status:in-progress"}]}'
: >"$gh_log"
reconcile_cleared_dependencies apply owner/repo 101 >/dev/null
[[ $(wc -l <"$gh_log") -eq 1 ]] || fail 'REST-to-GraphQL state normalization failed'
: >"$gh_log"
apply_cleared_dependency owner/repo "$initial" >/dev/null
edit=$(<"$gh_log")
[[ $edit == *'--remove-label status:blocked'* ]] || fail 'blocked label was not removed'
[[ $edit == *'--remove-label status:in-progress'* ]] || fail 'second status was not removed'
[[ $edit == *'--add-label status:ready'* ]] || fail 'ready label was not added'
[[ $(wc -l <"$gh_log") -eq 1 ]] || fail 'status swap used more than one edit call'

fake_mode=stale
if apply_cleared_dependency owner/repo "$initial" >/dev/null 2>"$tmp_dir/stale"; then
	fail 'stale dependent snapshot must cancel the transition'
fi
rg -q 'stale evaluation' "$tmp_dir/stale" || fail 'stale snapshot was not reported'

fake_mode=changed-body
if apply_cleared_dependency owner/repo "$initial" >/dev/null 2>"$tmp_dir/changed"; then
	fail 'changed dependency body must cancel the transition'
fi
rg -q 'dependency snapshot changed' "$tmp_dir/changed" ||
	fail 'changed dependency body was not reported'

fake_mode=conflict
if apply_cleared_dependency owner/repo "$initial" >/dev/null 2>"$tmp_dir/conflict"; then
	fail 'conflicting post-write status must be reported'
fi
rg -q 'conflicting status write' "$tmp_dir/conflict" || fail 'conflict was not actionable'

assert_text "$repo_root/content/skills/merge-cleanup/SKILL.md" \
	'reconcile_cleared_dependencies apply'
assert_text "$repo_root/content/skills/recover-orphans/SKILL.md" \
	'reconcile_cleared_dependencies plan'
assert_text "$repo_root/content/skills/triage-issues/SKILL.md" \
	'manual reassessment fallback'

printf 'cleared-dependencies-test: pass\n'
