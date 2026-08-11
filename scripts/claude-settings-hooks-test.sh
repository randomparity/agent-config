#!/usr/bin/env bash
set -euo pipefail

# Exercises the shipped Claude PreToolUse hook commands exactly as Claude Code runs
# them: the hook body is read out of settings.base.json and fed a tool_input JSON
# object on standard input. Both directions are asserted — a hook that blocks
# legitimate work is worked around, which is worse than no hook at all.
#
# These hooks are read out of the base file, and a private settings.overlay.json that
# defines hooks.PreToolUse used to replace that array wholesale — dropping every hook
# asserted here, silently. install.sh now refuses such an overlay rather than deploying
# the result, so the constraint is enforced instead of requested; see ADR 0043.
#
# Four accepted limits of the masked-exit hook, all consequences of scoping it to the
# known-masking targets rather than to any pipe of a guardrail command:
#   - `just ci | tee log` stays legal even though tee returns its own status;
#   - a filter reached through a non-tee pass-through (`just ci | cat | tail`) is missed;
#   - only `just ci` and `just verify` are recognised, since this file ships to every
#     repository and cannot enumerate one repository's recipe names;
#   - the filter list is tail, head, grep and rg, and the short-circuit list is `true`
#     and `:`, so `| sed`, `| awk`, `| cat`, `| less` and `|| echo failed` mask freely.
#
# Both hooks read the command as text, so both miss the indirection a text match cannot
# follow: backticks, `xargs`, and a command assembled from a variable. `bash -c`, `sh -c`
# and `eval` are recognised; the rest are accepted false negatives.

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

run_hook_without_jq() { # hook-command
	local payload
	payload=$(jq -nc '{tool_input: {command: "git clean -fd"}}')
	printf '%s' "$payload" | PATH="$SCRATCH:$PATH" bash -c "$1"
}

assert_fails_closed() { # hook-command label
	local status=0 output
	output=$(run_hook_without_jq "$1" 2>&1) || status=$?
	[[ $status == 2 ]] || fail "$2 must fail closed without jq, got exit $status: $output"
	[[ $output == BLOCKED:* ]] || fail "$2 must say why it failed closed: $output"
}

assert_fails_open() { # hook-command label
	local status=0 output
	output=$(run_hook_without_jq "$1" 2>&1) || status=$?
	[[ $status == 0 ]] || fail "$2 must fail open without jq, got exit $status: $output"
}

assert_posix_agrees() { # hook-command label command-string expected-status
	local status=0 output
	output=$(jq -nc --arg command "$3" '{tool_input: {command: $command}}' |
		sh -c "$1" 2>&1) || status=$?
	[[ $status == "$4" ]] || fail "$2 under sh must exit $4 for [$3], got $status: $output"
}

# `sh` is a POSIX shell only by convention, and where it is not one the assertions above
# establish nothing. Resolve it by what it accepts, not by where /bin/sh points: macOS
# reaches bash 3.2 through a real file rather than a symlink, and it is the shell `sh -c`
# lands on that decides the answer. `[[ ]]` is not in POSIX, so a shell that accepts it is
# an extended one — bash, zsh or ksh — and running a hook body under it re-runs an extended
# shell. Asking for a bash version instead would clear zsh and ksh, and would read an
# exported BASH_VERSION out of the ambient environment rather than out of the shell.
POSIX_SHELL=$(command -v sh || :)
[[ -n $POSIX_SHELL ]] || fail 'no sh on PATH: the hook bodies cannot be checked for POSIX'
if sh -c '[[ -n x ]]' 2>/dev/null; then
	SH_ACCEPTS_BASHISMS=yes
else
	SH_ACCEPTS_BASHISMS=no
fi

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

# The flag forms the issue names, combined and space-separated, in either order.
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
# git accepts any unambiguous abbreviation, so --f and --fo are --force.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean --f -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd /tmp; git clean --fo'
# clean.requireForce=false, inline or already in the repository config, deletes with no
# force flag at all — so the guard blocks every git clean that is not a dry run.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git -c clean.requireForce=false clean -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git -c clean.requireForce=0 clean'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -d'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -x'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -f -e node_modules'
# A flag that merely contains n or i is not a dry run.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --quiet'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fdx --exclude=node_modules'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd /tmp && git clean -fd --quiet'
# Shell wrappers are command positions too.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'bash -c "git clean -fd"'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'eval git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'sudo git clean -fdx'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'sudo -u dave git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'command git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'exec git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'nice git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'ionice -c3 git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'stdbuf -o0 git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'setsid git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'xargs -n1 git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' '! git clean -fd'
# `git submodule foreach` is the published recipe for cleaning a tree including its
# submodules, and it deletes: the argument runs in each submodule's working tree.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git submodule foreach git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' "git submodule foreach 'git clean -fd'"
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git submodule foreach --recursive git clean -fdx'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'GIT_DIR=/tmp/r/.git git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'env GIT_PAGER=cat git clean -fd'
# A command position survives leading indentation.
assert_blocked "$CLEAN_HOOK" 'git clean hook' $'if [ -d build ]; then\n  git clean -fd build\nfi'
# The pathspec separator does not end the argument list.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -- build/'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd sub && git clean -fd -- .'
# A preview beside a real delete must not disarm the guard for the delete.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -n && git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -n; git clean -fd'
assert_blocked "$CLEAN_HOOK" 'git clean hook' $'git clean -n\ngit clean -fd'

# A destructive guard that cannot read its input must not wave the command through.
assert_fails_closed "$CLEAN_HOOK" 'git clean hook'

# Forms that cannot force-delete stay legal.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean --dry-run'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -i'
# The dry-run letter may sit anywhere in a bundle: -nd is the standard preview.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -nd'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -ndx'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -nxd'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -id'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean --interactive'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -f -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -dn'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -n -- build/'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git submodule foreach git clean -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git status --porcelain'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git stash push --include-untracked'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git worktree remove /tmp/wt --force'
# A force flag and the word "clean" in the same line are not `git clean --force`.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git worktree remove /tmp/wt --force && echo clean'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git checkout -f main && make clean'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git rm -f clean'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git commit -m "make clean -f"'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git checkout -b cleanup-fix'
# Searching for the banned text is not running it: the hook must not fire on its own
# literal appearing inside a quoted argument.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'rg -n "git clean -fd" docs/'

MASK_HOOK=$(hook_command 'BLOCKED: piping')

# The two hooks share one command-position definition. Drift between the copies would make
# them disagree about what a command is, silently and in one direction only.
CLEAN_POS=$(printf '%s' "$CLEAN_HOOK" | sed -n "s/.*POS='\([^']*\)'.*/\1/p")
MASK_POS=$(printf '%s' "$MASK_HOOK" | sed -n "s/.*POS='\([^']*\)'.*/\1/p")
[[ -n $CLEAN_POS ]] || fail 'the git clean hook defines no POS pattern'
[[ $CLEAN_POS == "$MASK_POS" ]] || fail 'the two hooks define different POS patterns'

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
# The escape must occupy a command position ahead of the run, and must still be in effect
# when the pipeline runs. A pipefail that is commented out, echoed, scoped to a subshell
# that has already closed, or appended after the pipeline changes nothing about the exit
# code — and the block message names the phrase, so these are the cheapest routes out.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | tail # set -o pipefail'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'echo set -o pipefail && just ci | tail'
assert_blocked "$MASK_HOOK" 'masked exit hook' '(set -o pipefail); just ci | tail'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just ci | tail; set -o pipefail'
# Wrapper and conditional command positions.
assert_blocked "$MASK_HOOK" 'masked exit hook' 'timeout 600 just ci | tail'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'if just ci | tail; then echo ok; fi'
assert_blocked "$MASK_HOOK" 'masked exit hook' 'just -f Justfile ci | tail'
assert_blocked "$MASK_HOOK" 'masked exit hook' $'if true; then\n  just ci | tail\nfi'

# tee logging, bare runs, the documented pipefail escape, and unrelated pipelines
# stay legal.
assert_allowed "$MASK_HOOK" 'masked exit hook' 'set -o pipefail; just ci | tail -50'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'set -o pipefail && just ci | tail -50'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'set -euo pipefail; just ci | tail -50'
# The subshell that still encloses the pipeline is the honest one.
assert_allowed "$MASK_HOOK" 'masked exit hook' '(set -o pipefail; just ci | tail -50)'
assert_allowed "$MASK_HOOK" 'masked exit hook' $'set -euo pipefail\njust ci | tail -50'
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
# The recipe name is matched whole: ci-fast and verify-docs are not the guarded recipes.
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just ci-fast | tail'
assert_allowed "$MASK_HOOK" 'masked exit hook' 'just verify-docs | head'

# Accepted false positive, pinned so it is discoverable rather than surprising: the hooks
# read the command as text, so a banned command quoted inside an argument blocks as if it
# were being run — whenever a newline or a `;`, `&&` or `||` inside the quotes puts it at
# what looks like a command position. That covers heredocs, `git commit -m` bodies and
# `gh --body`. The hook message names the escape: pass the text through a file instead of
# quoting it inline.
assert_blocked "$CLEAN_HOOK" 'git clean hook' $'cat >note.md <<EOF\ngit clean -fd\nEOF'
assert_blocked "$CLEAN_HOOK" 'git clean hook' $'git commit -m "note\ngit clean -fd was refused"'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'gh issue comment 1 --body "tried && git clean -fd"'
assert_blocked "$MASK_HOOK" 'masked exit hook' $'cat >note.md <<EOF\njust ci | tail\nEOF'

# The destructive guard fails closed without jq; the advisory one fails open, because a
# missing jq would otherwise block every Bash call over a masking pattern that may not
# even be present.
assert_fails_open "$MASK_HOOK" 'masked exit hook'

# The shell Claude Code runs a hook body in is not this suite's to choose, so both hook
# bodies stay inside POSIX shell. Only a run whose sh rejects bashisms proves that, which
# across the environments this gate runs in is the ubuntu leg of .github/workflows/verify.yml
# alone: macOS ships bash 3.2 as /bin/sh, and so do the Fedora developer hosts. Everywhere
# else the suite reports the property unchecked instead of printing a green line it has not
# earned. That leaves one proving ground and nothing that turns red if it stops being one —
# enforcing it needs a workflow edit or a CI prerequisite, and is issue #136.
if [[ $SH_ACCEPTS_BASHISMS == yes ]]; then
	printf 'claude-settings-hooks-test: SKIP POSIX assertions: %s accepts [[ ]], so it is\n' \
		"$POSIX_SHELL"
	printf 'claude-settings-hooks-test: an extended shell and running the hook bodies under\n'
	printf 'claude-settings-hooks-test: it proves nothing. Only the ubuntu leg of\n'
	printf 'claude-settings-hooks-test: .github/workflows/verify.yml, where sh is dash, proves\n'
	printf 'claude-settings-hooks-test: them — this run did not check.\n'
	posix_verdict='POSIX assertions SKIPPED'
else
	assert_posix_agrees "$CLEAN_HOOK" 'git clean hook' 'git clean -fd' 2
	assert_posix_agrees "$CLEAN_HOOK" 'git clean hook' 'git clean -n' 0
	assert_posix_agrees "$MASK_HOOK" 'masked exit hook' 'just ci | tail' 2
	assert_posix_agrees "$MASK_HOOK" 'masked exit hook' 'just ci | tee /tmp/ci.log' 0
	posix_verdict="POSIX assertions ran under $POSIX_SHELL"
fi

printf 'claude-settings-hooks-test: ok (%s)\n' "$posix_verdict"
