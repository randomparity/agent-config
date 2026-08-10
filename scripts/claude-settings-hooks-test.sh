#!/usr/bin/env bash
set -euo pipefail

# Exercises the shipped Claude PreToolUse hook commands exactly as Claude Code runs
# them: the hook body is read out of settings.base.json and fed a tool_input JSON
# object on standard input. Both directions are asserted — a hook that blocks
# legitimate work is worked around, which is worse than no hook at all.
#
# Settings overlays replace arrays rather than merging them, so a private
# settings.overlay.json that defines hooks.PreToolUse drops every hook asserted here.
# Overlays must leave `hooks` alone.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETTINGS="$ROOT/agents/claude/shared/settings.base.json"

fail() {
	printf 'claude-settings-hooks-test: %s\n' "$*" >&2
	exit 1
}

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/claude-settings-hooks-test.XXXXXX")

cleanup() {
	case $SCRATCH in
	"${TMPDIR:-/tmp}"/claude-settings-hooks-test.*) rm -R "$SCRATCH" ;;
	*) printf 'claude-settings-hooks-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

printf '#!/usr/bin/env bash\nexit 127\n' >"$SCRATCH/jq"
chmod +x "$SCRATCH/jq"

hook_command() { # message-marker
	local marker=$1 matches count
	matches=$(jq -r --arg marker "$marker" '
		.hooks.PreToolUse[].hooks[]
		| select(.type == "command" and (.command | contains($marker)))
		| .command' "$SETTINGS")
	count=$(printf '%s' "$matches" | grep -c '' || :)
	[[ -n $matches && $count == 1 ]] ||
		fail "expected exactly one PreToolUse hook containing '$marker', found $count"
	printf '%s' "$matches"
}

run_hook() { # hook-command command-string
	jq -nc --arg command "$2" '{tool_input: {command: $command}}' | bash -c "$1"
}

assert_blocked() { # hook-command label command-string
	local status=0 output
	output=$(run_hook "$1" "$3" 2>&1) || status=$?
	[[ $status == 2 ]] || fail "$2 must block [$3] with exit 2, got $status"
	[[ $output == BLOCKED:* ]] || fail "$2 must explain the block for [$3]: $output"
}

assert_allowed() { # hook-command label command-string
	local status=0 output
	output=$(run_hook "$1" "$3" 2>&1) || status=$?
	[[ $status == 0 ]] || fail "$2 must allow [$3], got exit $status: $output"
}

assert_fails_closed() { # hook-command label
	local status=0 output payload
	payload=$(jq -nc '{tool_input: {command: "ls"}}')
	output=$(printf '%s' "$payload" | PATH="$SCRATCH:$PATH" bash -c "$1" 2>&1) || status=$?
	[[ $status == 2 ]] || fail "$2 must fail closed without jq, got exit $status: $output"
	[[ $output == BLOCKED:* ]] || fail "$2 must say why it failed closed: $output"
}

assert_deny_entry() { # pattern
	jq -e --arg pattern "$1" '.permissions.deny | index($pattern)' "$SETTINGS" >/dev/null ||
		fail "permissions.deny is missing $1"
}

# The deny entries are defence in depth for the simple, uncompounded command. Their glob
# semantics belong to Claude Code and are not exercised here, so a green run establishes
# that the entries are present, not that they match. The hooks are what this suite proves.
assert_deny_entry 'Bash(git clean -f*)'
assert_deny_entry 'Bash(git clean *-f*)'

CLEAN_HOOK=$(hook_command 'BLOCKED: git clean')

# Combined and space-separated force flags, in either order, with or without -d.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -df'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -f -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -d -f'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -xfd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean --force -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -d --force'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -f'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git   clean   -fd'
# Forms a Bash(...) deny prefix pattern cannot reach.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd /tmp && git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git status; git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git -C /tmp/repo clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git --no-pager clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' $'git status\ngit clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' '(git clean -fd)'
assert_blocked "$CLEAN_HOOK" 'git clean hook' '{ git clean -fd; }'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'for d in a b; do git clean -fd; done'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git status & git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'timeout 60 git clean -fd'
# git accepts any unambiguous abbreviation of --force.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean --f -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd /tmp; git clean --fo'
# clean.requireForce=false deletes with no force flag at all.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git -c clean.requireForce=false clean -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git -c clean.requireForce=0 clean'

# A destructive guard that cannot read its input must not wave the command through.
assert_fails_closed "$CLEAN_HOOK" 'git clean hook'

# Forms that cannot force-delete stay legal.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean --dry-run'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -i'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git status --porcelain'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git stash push --include-untracked'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git worktree remove /tmp/wt --force'
# A force flag and the word "clean" in the same line are not `git clean --force`.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git worktree remove /tmp/wt --force && echo clean'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git checkout -f main && make clean'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git rm -f clean'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git commit -m "make clean -f"'
# Searching for the banned text is not running it: the hook must not fire on its own
# literal appearing inside a quoted argument.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'rg -n "git clean -fd" docs/'

MASK_HOOK=$(hook_command 'BLOCKED: piping')

assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | tail'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | tail -20'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | head -50'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | grep -i error'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci >/dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci > /dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci >/dev/null 2>&1'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci 2>/dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci &>/dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci || true'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just verify | tail -5'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just verify || true'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'cd /tmp/repo && just ci | head'
# `rg` is the grep this repository's own instructions mandate.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | rg -n error'
# A redirect ahead of the pipe must not carry the run past the check.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci 2>&1 | tail -20'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci 2>&1 | grep -i error'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just verify 2>&1 | head'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci >>/dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci >&/dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci || :'
# tee is legal, but a filter after it masks exactly as much as one without it.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | tee /tmp/ci.log | grep -i error'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci 2>&1 | tee /tmp/ci.log | tail -20'
# pipefail rescues the pipe, not a discarded or swallowed exit code.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'set -o pipefail; just ci >/dev/null'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'set -o pipefail; just ci || true'
# The escape must occupy a command position, not merely appear in the text.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | tail # set -o pipefail'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'echo set -o pipefail && just ci | tail'
# Wrapper and conditional command positions.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'timeout 600 just ci | tail'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'if just ci | tail; then echo ok; fi'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just -f Justfile ci | tail'

# tee logging, bare runs, the documented pipefail escape, and unrelated pipelines
# stay legal.
assert_allowed "$MASK_HOOK" 'masked exit hook' 'set -o pipefail; just ci | tail -50'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'set -o pipefail && just ci | tail -50'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'set -euo pipefail; just ci | tail -50'
assert_allowed "$MASK_HOOK" 'masked exit hook' '(set -o pipefail; just ci | tail -50)'
assert_allowed "$MASK_HOOK" 'masked exit hook' $'set -euo pipefail\njust ci | tail -50'
# The escape is anchored to a command position, not ordered against the run: pipefail
# after the pipeline reads as a deliberate bypass, not a mistake worth blocking.
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci | tail; set -o pipefail'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci > /tmp/ci.log'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci | rgx-report'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just verify'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci | tee /tmp/ci.log'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci 2>&1 | tee /tmp/ci.log'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just --list | head'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'git log --oneline | head -5'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'gh pr checks 1 | grep fail'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'rg -n "just ci | tail" AGENTS.md'
# tail/head/grep is a prefix of longer commands that mask nothing.
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci | tailscale-status'

# Accepted false positive, pinned so it is discoverable rather than surprising: grep
# treats every line of a multi-line command as its own command position, so banned text
# inside a heredoc blocks too. Write such files with the editor tool, not a heredoc.
assert_blocked "$CLEAN_HOOK" 'git clean hook' $'cat >note.md <<EOF\ngit clean -fd\nEOF'
assert_blocked "$MASK_HOOK" 'masked exit hook' $'cat >note.md <<EOF\njust ci | tail\nEOF'

printf 'claude-settings-hooks-test: ok\n'
