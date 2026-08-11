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
# Both hooks read the command as text. The destructive guard fires only where three things
# hold at once: a recognised command position, then an unbroken `git ... clean` on that one
# line, then every token between `clean` and the next `;`, `&`, `|`, `)` or end of line
# accounted for by its option grammar. Those are separate axes, and the gaps below are
# grouped by the one each exploits — `sudo \git clean -fd` is allowed despite sudo being a
# recognised position, because it fails the second. Every form named was run against the
# shipped hook body.
#
# Position. `xargs -n1 git clean -fd` blocks, correcting an earlier claim here that both
# mechanisms miss xargs: 2cbe92b put xargs in the alternation. POS in settings.base.json is
# the authoritative list and is not restated here — it covers the separators, the shell
# keywords, a leading `!`, a `VAR=value` prefix, the `-c` shells, `eval`,
# `git submodule foreach`, and an enumerated set of wrapper commands. Enumerated is the
# operative word: the wrappers outside it are an open class, not a fixed shortfall. Five
# that allow a destructive clean are `trap "git clean -fd" EXIT`,
# `ssh host git clean -fd`, `find . -execdir git clean -fd \;` (`-exec` likewise),
# `flock /tmp/l git clean -fd` and `su -c "git clean -fd"`. None is closed here, and
# enumerating them is not the same as bounding them.
#
# The command word is matched as the literal `git`, so qualifying its path defeats the
# whole pattern: `/usr/bin/git clean -fd` and `./git clean -fd` are allowed, and a
# recognised wrapper does not rescue it — `sudo /usr/bin/git clean -fd` is allowed too.
# That is issue #156.
#
# Text. These break the token run itself, so no alternation entry closes them and chasing
# them is a matcher arms race this approach cannot win:
#   - quoting and escaping a shell strips and a matcher does not — `\git clean -fd`,
#     `git "clean" -fd`, `git cl""ean -fd`. Quoting the command whole is different: it
#     still fires where a recognised position precedes the quotes (`bash -c "git clean
#     -fd"`) or a separator inside them makes one (the accepted false positive below).
#     `su -c` above shows the position axis still governs;
#   - a backslash-newline continuation that lands inside the token run, since the match is
#     per line. Splitting between `git` and `clean` evades, and so does a backslash
#     abutting `clean` — `git clean\` then a newline then ` -fd` rejoins to exactly
#     `git clean -fd` but leaves the matcher a `clean\` token. Only a continuation after
#     the space that follows `clean`, or one inside `-fd`, is still caught;
#   - a command assembled rather than written — `C="git clean -fd"; $C`, backticks, or
#     `$(echo git clean -fd)`. A literal `$(git clean -fd)` blocks, since `(` is a
#     position.
# These are deliberate routes around the guard. The wrappers above, and the path-qualified
# git with them, are not: they are ordinary usage the guard does not reach, so a clean on a
# remote host, in a nested checkout, or through `/usr/bin/git` in a script is unguarded
# whether or not anyone meant to evade. A form missing from this comment is not thereby
# covered. All of it applies to the masked-exit guard too, which is
# the same text matcher over the same POS: `\just ci | tail` and `C="just ci | tail"; $C`
# were run and are allowed. Only the Flags section below is specific to the destructive
# guard.
#
# Flags. The guard reads the tokens after `clean` in two sections: options, then a pathspec
# tail that a bare `--` or the exact token `--end-of-options` opens. The command is allowed
# when no parse of the token run reaches the separator — not when a left-to-right scan meets
# a token it cannot consume. `grep -E` backtracks across the alternatives, so a token run
# that any parse can consume matches. In the tail every remaining token is consumed whatever
# it looks like. Each form named below was run against the shipped hook body, and against
# git 2.55.0 to establish which of them delete.
#
# Consumed in the option section, so they do not exempt the command:
#   - a `--` option whose first letter is not d, i or e — `--quiet`, `--force`, `--f`,
#     `--fo`, and `--no-dry-run`, which deletes;
#   - `--e` and the longer prefixes of `--exclude`, together with the pattern, which is
#     mandatory as it is for git: attached as `--exclude=-n`, or the following token as in
#     `--exclude -n`. Both delete. git resolves every prefix from `--e` up, so `--e pat`
#     and `--exc=pat` are that option too;
#   - a single-dash bundle holding no n, i or e — `-fd`, `-fdx`, `-x`, `-q`;
#   - a single-dash bundle where e precedes any n or i, together with the pattern -e takes,
#     again mandatory: the rest of the token where there is one (`-epat`, `-e-n`, `-fen`),
#     otherwise the following token (`-e -n`, `-fde -n`, `-f -e node_modules`). All of those
#     delete. In a bundle everything after the first e is -e's value, so the n in `-fen` is
#     part of a pattern and not a preview. The value is not optional because a parse that
#     skipped it would let the next token be re-read as a fresh `-e` or as the `--` opening
#     the tail, swallowing a preview git did honour: `git clean -e -e -n`,
#     `git clean -fde -e -n` and `git clean -e -- -n` all preview and are pinned as allowed;
#   - a bare `-`, which git reads as an ordinary pathspec — `git clean -fdx - .` deletes;
#   - any other token that does not begin with `-`, which is a pathspec.
#
# Stops the option section, so the command is allowed:
#   - a single-dash bundle where n or i precedes any e — `-n`, `-i`, `-fdn`, `-nd`, `-id`;
#   - a `--` option whose first letter is d or i — `--dry-run`, `--interactive`, and the
#     abbreviations `--d` and `--i`. All four preview;
#   - an option wanting a value that has none, and a `--e…` spelling that is neither an
#     `--exclude` prefix nor the exact `--end-of-options` — `git clean -fd -e`,
#     `git clean -fd --exclude`, `git clean -fd --e` and `git clean -fd --end`. git rejects
#     all four for a missing value or an unknown option, so none of them deletes. These are
#     the tokens the grammar does not account for, and the reason each is safe is git's
#     rejection rather than anything the guard does.
#
# The letter rules encode git 2.55.0's option table for `clean` rather than a parser for it:
# d and i are the only long names that mean a preview, `--end-of-options` is the only
# value-less long option beginning with e, and -e/--exclude is the only option taking a
# value. `--end-of-options` is spelled in full or not at all — parse-options does not
# abbreviate it, and `--end` is an unknown option — which is what lets the two `--e…` rules
# sit side by side. An option added to git that broke any of those premises would be
# misread and nothing here would notice.
#
# The guard reads where a preview flag sits, not whether a later flag cancels it. git
# options are last-one-wins, so `git clean -fdn --no-dry-run` and `git clean -fn
# --no-dry-run` delete and are allowed — the `-fdn` stops the option section before the
# negation is reached. That is unchanged from before #141 and is issue #160; the deny
# entries reach the uncompounded form, and `cd sub && git clean -fdn --no-dry-run` has no
# cover.
#
# Issue #141 is what the two sections and the mandatory -e value close. Before them the
# option section ran to the end of the line, so a preview flag git would not parse as a flag
# exempted the command: `git clean -fd -- build/ -n` and `git clean -fd -e -n` were allowed
# and deleted. The two `git clean` deny entries were the only cover, and they reach the
# uncompounded command only, so `cd sub && git clean -fd -- build/ -n` had none at all. Both
# are pinned below. The deny entries stay in place; whether they are still wanted is a
# separate decision and not a consequence of this fix.
#
# A differential over 1838 generated invocations — each run against git 2.55.0 in a
# throwaway repository and against the shipped hook body — found the two #160 forms as the
# only commands git deletes on and the guard allows, and no command git previews on that the
# guard blocks. Run against the pre-#141 body over the same set, 97 commands that delete
# move from allowed to blocked and none that preview move the other way; the 112 that stop
# being blocked are all ones git rejects for a missing `-e`/`--exclude` value. The token
# pool is what that bounds: the flag bundles, `--` long options including `--e…` and
# `--end-of-options`, the two separators, a bare `-` and plain pathspecs, in runs of one to
# three. It does not bound the position and text axes above, which the corpus does not vary,
# and a token outside the pool is unmeasured rather than known-good.
#
# One consequence of making the `-e` value mandatory: a token run that fails to parse is
# rescanned from each later start position, so the guard's cost is quadratic in the number
# of `git clean` occurrences on a single line. Measured on the shipped body, a line of
# repeated `git clean -e ` costs 8 ms at 400 occurrences, 68 ms at 3200 and 997 ms at 12800
# (166 KB). Ordinary input is unaffected — one `git clean` with 4000 trailing options is
# 11 ms — so this is recorded as the cause of a future latency report, not as a reason to
# restructure the pattern.

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
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --exclude=-n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --no-dry-run'
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
# git stops parsing options at `--`, so every token after it is a pathspec. A preview flag
# there is a filename, and each of these deletes on git 2.55.0.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -- build/ -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fdx -- . -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -- -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -- . --dry-run'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -- -i'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -q -- -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd sub && git clean -fd -- build/ -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git submodule foreach git clean -fd -- . -n'
# -e/--exclude takes the next token as its pattern, so a preview flag in that slot is a
# value, not a flag. In a short bundle everything after the first e is that value, which is
# why -fen and -fde -n delete. All five were run against git 2.55.0.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -e -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --exclude -n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -e-n'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fen'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fde -n'
# git reads a bare `-` as an ordinary pathspec, so it suppresses nothing.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fdx - .'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd sub && git clean -fdx - .'
# `--end-of-options` is the other separator: parse-options ends option parsing there too,
# so it opens the pathspec tail rather than reading as an --exclude prefix.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --end-of-options'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'cd sub && git clean -fd --end-of-options'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --end-of-options build/ --dry-run'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --end-of-options -n'
# Every --exclude prefix from --e up carries its pattern.
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --e pat'
assert_blocked "$CLEAN_HOOK" 'git clean hook' 'git clean -fd --exc=pat'
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
# The other side of the two rules above: a preview flag ahead of the separator is still a
# preview whatever pathspecs follow, and once -e has taken its pattern the next token is a
# flag again. These pin the over-reach direction — they stay green if the fix is reverted
# and redden if it blocks a real dry run. Each previewed rather than deleted on git 2.55.0.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -n -- -f'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -q -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -e pat -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -epat -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -fd -epat -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean --exclude pat -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean --exclude=pat -n'
# An option-shaped exclude pattern must not let the matcher re-read the next token as a
# fresh -e or as the separator, which would swallow a preview git did honour.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -e -e -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -fde -e -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -e -- -n'
# A pathspec that is a bare `-` does not disarm a preview flag either.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean - -n'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -fd - -n'
# A preview flag ahead of `--end-of-options` is still in an option position.
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -n --end-of-options build/'
assert_allowed "$CLEAN_HOOK" 'git clean hook' 'git clean -i --end-of-options .'
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
# even be present. Fail-open is also the shape of the three hooks that predate these two —
# the rm -rf, push-to-main and rg guards each read the command without checking jq's exit
# status — so the destructive guard is the exception, deliberately. jq is a declared
# prerequisite: install.sh requires it at install time (install.sh:388) and
# `just tools-check` (Justfile:33, reached from `just verify` at Justfile:152) re-checks
# it. That second half is this repository only. In the other repositories these hooks ship
# to, a jq that leaves PATH after install makes the advisory guard quiet, with no gate to
# notice.
#
# Only jq is guarded. Any other helper a guard calls can fail the same way unchecked: with
# a grep that exits 2 on PATH, the destructive guard exits 0 on a real `git clean -fd`,
# because Claude Code blocks on exit 2 alone. That is issue #139.
#
# The masked-exit guard also depends on awk, but the consequence is the opposite of the jq
# one. awk extracts only the text preceding `just ci`, which the `set -o pipefail`
# exemption is tested against; a broken awk empties it, losing the exemption, so
# `set -o pipefail; just ci | tail` is blocked. A false positive, not a hole.
assert_fails_open "$MASK_HOOK" 'masked exit hook'

# The shell Claude Code runs a hook body in is not this suite's to choose, so both hook
# bodies stay inside POSIX shell. Only a run whose sh rejects bashisms proves that, which
# across the environments this gate runs in is the ubuntu leg of .github/workflows/verify.yml
# alone: macOS ships bash 3.2 as /bin/sh and the Fedora developer hosts ship bash 5, so
# neither can reject a bashism. Everywhere else the suite reports the property unchecked
# instead of printing a green line it has not earned. Only one proving ground is left, and
# nothing turns red if it stops being one — enforcing that needs a workflow edit or a CI
# prerequisite, and is issue #136.
if [[ $SH_ACCEPTS_BASHISMS == yes ]]; then
	printf 'claude-settings-hooks-test: %s\n' \
		"SKIP POSIX assertions: $POSIX_SHELL accepts [[ ]], so it is" \
		'an extended shell and running the hook bodies under' \
		'it proves nothing. Only the ubuntu leg of' \
		'.github/workflows/verify.yml, where sh is dash, proves' \
		'them — this run did not check.'
	posix_verdict='POSIX assertions SKIPPED'
else
	assert_posix_agrees "$CLEAN_HOOK" 'git clean hook' 'git clean -fd' 2
	assert_posix_agrees "$CLEAN_HOOK" 'git clean hook' 'git clean -n' 0
	assert_posix_agrees "$MASK_HOOK" 'masked exit hook' 'just ci | tail' 2
	assert_posix_agrees "$MASK_HOOK" 'masked exit hook' 'just ci | tee /tmp/ci.log' 0
	posix_verdict="POSIX assertions ran under $POSIX_SHELL"
fi

printf 'claude-settings-hooks-test: ok (%s)\n' "$posix_verdict"
