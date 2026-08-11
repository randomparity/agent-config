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
# consumable by its flag alternation. Those are separate axes, and the gaps below are
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
# Flags. The guard walks the tokens after `clean`, up to that same separator, and stops at
# the first one its alternation cannot consume, which leaves the whole command unmatched
# and allowed. Two rules, not one: a single-dash token stops it when n or i appears
# anywhere in it (`-n`, `-i`, `-fdn`), while a `--` token stops it only on the first letter
# after the dashes being d or i — so `--dry-run` and `--interactive` are allowed while
# `--quiet` and `--force` still block, as the assertions below pin, and `--exclude=-n`
# blocks despite ending in -n. That last one was run against the hook body and is not
# pinned. A token no alternative consumes at all, such as a bare `-`, stops it too. git
# need not agree that a stopping token is a preview, and `--` is not what makes the
# difference: after `--` a flag is a
# pathspec, so `git clean -fd -- build/ -n` deletes and is allowed (git 2.55.0), and in
# `git clean -fd -e -n` the -n is consumed as -e's exclude pattern. The git clean deny
# entries are the only cover left, and they reach the simple uncompounded command only
# (see the note on them below), so `cd sub && git clean -fd -- build/ -n` has no cover at
# all. Issue #141.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETTINGS="$ROOT/agents/claude/shared/settings.base.json"

fail() {
	printf 'claude-settings-hooks-test: %s\n' "$*" >&2
	exit 1
}

# The push-to-main hook returns 0 unconditionally when GT_REFINERY=1, before it evaluates
# anything. That is an operator escape hatch, not a defect, but it is read from the ambient
# environment — so a developer who has it exported would run a different suite from CI's, and
# the push assertions below would fail for a reason that has nothing to do with the hook.
# Clear it here so every run asserts the hook, not the environment. ADR 0056 records the one
# consequence for helper failure.
unset GT_REFINERY

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/claude-settings-hooks-test.XXXXXX")

cleanup() {
	case $SCRATCH in
	"${TMPDIR:-/tmp}"/claude-settings-hooks-test.*) rm -R "$SCRATCH" ;;
	*) printf 'claude-settings-hooks-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

# One stub directory per helper the hook bodies shell out to. A stub exits 2 — the status a
# helper returns for an error, as opposed to grep's 1, which is an answer. jq gets a second
# stub exiting 127, the status a shell reports for a command that is not on PATH at all, so
# the "jq uninstalled" and "jq broken" paths are distinct cases rather than one assumed to
# stand for the other. Prepending a stub directory shadows only that helper; the rest of
# PATH still resolves, so each column of the matrix isolates one failure.
for helper in jq grep awk printf echo; do
	mkdir -p "$SCRATCH/broken-$helper"
	printf '#!/usr/bin/env bash\nexit 2\n' >"$SCRATCH/broken-$helper/$helper"
	chmod +x "$SCRATCH/broken-$helper/$helper"
done
mkdir -p "$SCRATCH/missing-jq"
printf '#!/usr/bin/env bash\nexit 127\n' >"$SCRATCH/missing-jq/jq"
chmod +x "$SCRATCH/missing-jq/jq"

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

# The payload is built before PATH is narrowed, so the stub never has to serve this jq call:
# a stub that broke the harness's own input would prove nothing about the hook.
run_hook_with_path() { # hook-command path-prefix command-string
	local payload
	payload=$(jq -nc --arg command "$3" '{tool_input: {command: $command}}')
	printf '%s' "$payload" | PATH="$1:$PATH" bash -c "$2"
}

# The optional expected-substring argument is what makes these assertions bite. Exit status
# alone does not distinguish a guard that refused because it detected the failure from one
# that refused by accident — the masked-exit guard's awk branch is exactly that case: delete
# its check and a broken awk still yields exit 2, via an empty extraction that loses the
# pipefail exemption. Status-only assertions stayed green through that deletion. Naming the
# helper in the message is also the entire benefit claimed for failing closed uniformly, so
# leaving it unasserted would leave the change's rationale untested.
assert_fails_closed() { # hook-command label stub-dir command-string [expected-substring]
	local status=0 output
	output=$(run_hook_with_path "$SCRATCH/$3" "$1" "$4" 2>&1) || status=$?
	[[ $status == 2 ]] ||
		fail "$2 must fail closed under $3 for [$4], got exit $status: $output"
	[[ $output == BLOCKED:* ]] || fail "$2 must say why it failed closed under $3: $output"
	[[ -z ${5:-} || $output == *"$5"* ]] ||
		fail "$2 under $3 must name the failure ('$5') for [$4]: $output"
}

assert_unaffected_by() { # hook-command label stub-dir command-string status [expected-substring]
	local status=0 output
	output=$(run_hook_with_path "$SCRATCH/$3" "$1" "$4" 2>&1) || status=$?
	[[ $status == "$5" ]] ||
		fail "$2 under $3 must still exit $5 for [$4], got $status: $output"
	[[ -z ${6:-} || $output == *"$6"* ]] ||
		fail "$2 under $3 must name the failure ('$6') for [$4]: $output"
}

# The strongest statement of fail-closed available without naming a helper: with no PATH at
# all, every external command a body reaches for fails, including one added after this file
# was written. A body that still refuses its triggering command refuses it for reasons its
# author did not have to enumerate. The shell running the body has to be named by absolute
# path: an empty PATH is also the one thing that stops the harness finding the shell itself.
BASH_BIN=$(command -v bash) || fail 'no bash on PATH'

assert_fails_closed_without_path() { # hook-command label command-string
	local status=0 output payload
	payload=$(jq -nc --arg command "$3" '{tool_input: {command: $command}}')
	output=$(printf '%s' "$payload" | PATH='' "$BASH_BIN" -c "$1" 2>&1) || status=$?
	[[ $status == 2 ]] ||
		fail "$2 must fail closed with an empty PATH for [$3], got exit $status: $output"
	# Contains rather than starts-with: with no PATH the shell prints its own
	# `jq: command not found` to the same stderr ahead of the hook's message. Both reach
	# Claude Code, and the requirement is that the explanation is among them.
	[[ $output == *BLOCKED:* ]] || fail "$2 must say why it failed closed with no PATH: $output"
}

# Feeds a raw payload rather than a command string: these cases are about input the hook
# cannot read a command out of, which run_hook's jq -n construction can never produce.
assert_payload_fails_closed() { # hook-command label payload description
	local status=0 output
	output=$(printf '%s' "$3" | bash -c "$1" 2>&1) || status=$?
	[[ $status == 2 ]] ||
		fail "$2 must fail closed on $4, got exit $status: $output"
	[[ $output == *BLOCKED:* ]] || fail "$2 must say why it failed closed on $4: $output"
}

assert_payload_allowed() { # hook-command label payload description
	local status=0 output
	output=$(printf '%s' "$3" | bash -c "$1" 2>&1) || status=$?
	[[ $status == 0 ]] || fail "$2 must allow $4, got exit $status: $output"
}

assert_posix_agrees() { # hook-command label command-string expected-status
	local status=0 output
	output=$(jq -nc --arg command "$3" '{tool_input: {command: $command}}' |
		sh -c "$1" 2>&1) || status=$?
	[[ $status == "$4" ]] || fail "$2 under sh must exit $4 for [$3], got $status: $output"
}

# The helper-failure branches are the newest shell in these bodies and the least like the
# rest of them: a function that exits the shell from inside a `&&` chain and from inside a
# `!` negation. Asserting them only under bash would leave the code this file exists to
# prove POSIX exercised under one shell and claimed for another.
assert_posix_fails_closed() { # hook-command label stub-dir command-string [expected-substring]
	local status=0 output payload
	payload=$(jq -nc --arg command "$4" '{tool_input: {command: $command}}')
	output=$(printf '%s' "$payload" | PATH="$SCRATCH/$3:$PATH" sh -c "$1" 2>&1) || status=$?
	[[ $status == 2 ]] ||
		fail "$2 under sh must fail closed under $3 for [$4], got exit $status: $output"
	[[ $output == BLOCKED:* ]] ||
		fail "$2 under sh must say why it failed closed under $3: $output"
	[[ -z ${5:-} || $output == *"$5"* ]] ||
		fail "$2 under sh must name the failure ('$5') under $3: $output"
}

# Enumerated, not named. Everything else in this file reaches a hook through hook_command,
# which finds it by a string from its own block message — so a hook added later is simply
# absent from the suite, and absence is not a failure. This reads the array itself, so the
# floor below applies to a sixth hook nobody has written yet: whatever it guards, it may not
# answer 0 when it could not evaluate its input. A hook that genuinely should permit the
# call when its helpers are broken has to say so by failing this assertion and being argued
# for, which is the recorded-decision requirement expressed as a gate.
all_hook_commands() {
	jq -r '.hooks.PreToolUse[].hooks[] | select(.type == "command") | .command' "$SETTINGS"
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

# A destructive guard that cannot read its input must not wave the command through. The full
# helper-failure matrix for every hook is at the end of this file; this pair is the case the
# guard was built around, kept beside the assertions it qualifies.
assert_fails_closed "$CLEAN_HOOK" 'git clean hook' missing-jq 'git clean -fd' 'jq missing or failed'
assert_fails_closed "$CLEAN_HOOK" 'git clean hook' broken-grep 'git clean -fd' 'grep exited'

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

# Helper failure. Claude Code blocks on exit 2 alone: every other non-zero status from a
# PreToolUse hook is a non-blocking error, and the tool call proceeds. So a hook that dies
# for a reason its body did not anticipate does not refuse the command — it permits it. All
# five hooks now treat a helper that could not answer as a reason to refuse, and the
# per-hook assertions below pin that one hook at a time (issue #139, ADR 0056).
#
# The helpers are jq, grep and awk. printf and echo are shell builtins in every shell these
# bodies run under, so a PATH entry named printf or echo is never reached and cannot fail;
# the assertions below prove that rather than assuming it, which is what makes the list of
# three a list and not a guess.
#
# Reading the input is the same problem as running a helper, and was the same defect. jq -r
# prints the string "null" for an absent field and exits 0, so a payload carrying no command
# left every guard matching against the literal text "null" and permitting the call. The
# capture is jq -er, whose non-zero status on null the existing || branch already handled.
# The enumeration loop asserts it for every hook.
#
# The reason uniform fail-closed costs nothing extra is worth stating, because it is not
# obvious from any one hook: these five run on the same Bash tool call, and a single exit 2
# blocks it. The destructive git clean guard has failed closed on jq since it was written,
# so on a broken jq the call was already refused whatever the other four returned. Making
# them fail closed too changes which diagnostics print, not which commands run — the cost
# was already paid, and paying it visibly is better than four hooks whose silence depends
# on a fifth hook's behaviour that nothing states.
#
# jq is a declared prerequisite: install.sh requires it at install time (install.sh:388)
# and `just tools-check` (Justfile:33, reached from `just verify` at Justfile:152) re-checks
# it. That second half is this repository only; in the other repositories these hooks ship
# to, nothing re-checks it, which is why the hooks check it themselves.
#
# awk is checked, but only where its answer is read, and the placement is the whole point.
# The masked-exit guard uses awk to extract the text preceding `just ci`, and exactly one
# test reads that text: the `set -o pipefail` exemption. So the awk call sits inside the
# branch that has already matched a masking pattern, and a broken awk refuses there, naming
# awk. Placed where it used to be — before the `if`, run on every Bash call — the same check
# would refuse every command, including the overwhelming majority that match no masking
# pattern and never read the result. Lazy placement blocks exactly the command shapes an
# unguarded broken awk already blocked, and improves only the diagnostic; eager placement
# would have blocked everything. That difference is the decision, not whether to check awk.
#
# The consequence for `set -o pipefail; just ci | tail -50` is unchanged either way: with awk
# broken it is refused, though with awk healthy the exemption allows it. That is a false
# positive, not a hole. Issue #113's text says the opposite and is wrong. Both halves are
# pinned below.
assert_fails_closed "$CLEAN_HOOK" 'git clean hook' broken-jq 'git clean -fd' 'jq missing or failed'
assert_fails_closed "$MASK_HOOK" 'masked exit hook' missing-jq 'just ci | tail' 'jq missing or failed'
assert_fails_closed "$MASK_HOOK" 'masked exit hook' broken-grep 'just ci | tail' 'grep exited'
# awk: refused where its answer is read, inert everywhere else. The first line is the
# accepted false positive — with awk healthy this command is allowed, as the exemption
# assertions above pin. The two `0` lines are what lazy placement buys: neither command
# reaches the awk call, so a broken awk does not touch them.
assert_fails_closed "$MASK_HOOK" 'masked exit hook' broken-awk \
	'set -o pipefail; just ci | tail -50' 'awk exited'
assert_unaffected_by "$MASK_HOOK" 'masked exit hook' broken-awk 'just ci | tee /tmp/ci.log' 0
assert_unaffected_by "$MASK_HOOK" 'masked exit hook' broken-awk 'git status --porcelain' 0
assert_unaffected_by "$MASK_HOOK" 'masked exit hook' broken-awk 'just ci | tail' 2 'awk exited'

# The three hooks that predate the two above had no assertions at all, and each read the
# command without checking any helper's exit status. A fail-closed assertion on its own
# would pass just as well against a hook that blocks everything, so each is paired with the
# triggering and benign commands that make the pair bite.
RM_HOOK=$(hook_command 'BLOCKED: Use trash')
PUSH_HOOK=$(hook_command 'BLOCKED: Use feature branches')
RG_HOOK=$(hook_command 'BLOCKED: ripgrep is recursive')

assert_blocked "$RM_HOOK" 'rm -rf hook' 'rm -rf /tmp/scratch'
assert_blocked "$RM_HOOK" 'rm -rf hook' 'cd /tmp && rm -fr build'
assert_allowed "$RM_HOOK" 'rm -rf hook' 'trash /tmp/scratch'
assert_allowed "$RM_HOOK" 'rm -rf hook' 'rm /tmp/one-file'
assert_allowed "$RM_HOOK" 'rm -rf hook' 'git status --porcelain'

assert_blocked "$PUSH_HOOK" 'push-to-main hook' 'git push origin main'
assert_blocked "$PUSH_HOOK" 'push-to-main hook' 'git push origin master'
# The GT_REFINERY escape hatch, and what it does when a helper is broken. The hatch sits
# after the jq capture and before the grep, which is main's statement order kept unchanged —
# so a broken jq refuses even under the hatch, while a broken grep is never reached and the
# hatch still permits. That split is a consequence of statement order rather than a designed
# boundary, so it is pinned here and recorded in ADR 0056 rather than left to be rediscovered.
# Reordering the hatch is a change to its meaning and is not made here.
(
	export GT_REFINERY=1
	assert_allowed "$PUSH_HOOK" 'push-to-main hook under GT_REFINERY' 'git push origin main'
	assert_fails_closed "$PUSH_HOOK" 'push-to-main hook under GT_REFINERY' missing-jq \
		'git push origin main' 'jq missing or failed'
	assert_unaffected_by "$PUSH_HOOK" 'push-to-main hook under GT_REFINERY' broken-grep \
		'git push origin main' 0
) || exit 1
assert_allowed "$PUSH_HOOK" 'push-to-main hook' 'git push origin feat/thing-1'
assert_allowed "$PUSH_HOOK" 'push-to-main hook' 'git push -u origin HEAD'

assert_blocked "$RG_HOOK" 'rg -r hook' 'rg -r foo src/'
assert_allowed "$RG_HOOK" 'rg -r hook' 'rg -n foo src/'
assert_allowed "$RG_HOOK" 'rg -r hook' 'rg -ln foo src/'

for stub in missing-jq broken-jq broken-grep; do
	case $stub in
	broken-grep) want='grep exited' ;;
	*) want='jq missing or failed' ;;
	esac
	assert_fails_closed "$RM_HOOK" 'rm -rf hook' "$stub" 'rm -rf /tmp/scratch' "$want"
	assert_fails_closed "$PUSH_HOOK" 'push-to-main hook' "$stub" 'git push origin main' "$want"
	assert_fails_closed "$RG_HOOK" 'rg -r hook' "$stub" 'rg -r foo src/' "$want"
	# Failing closed is a property of the hook, not of the command: a guard that cannot read
	# or evaluate its input does not know the command was benign either.
	assert_fails_closed "$RM_HOOK" 'rm -rf hook' "$stub" 'ls -la' "$want"
	assert_fails_closed "$CLEAN_HOOK" 'git clean hook' "$stub" 'git clean -n' "$want"
	assert_fails_closed "$MASK_HOOK" 'masked exit hook' "$stub" 'just ci' "$want"
	assert_fails_closed "$PUSH_HOOK" 'push-to-main hook' "$stub" 'git push origin feat/x' "$want"
	assert_fails_closed "$RG_HOOK" 'rg -r hook' "$stub" 'rg -n foo src/' "$want"
done

# printf and echo resolve to builtins, so a broken one on PATH is never reached. Asserting
# the healthy verdict under those stubs is what turns "the helpers are jq, grep and awk"
# from an assumption into a checked claim: were either reached, these would go red.
for stub in broken-printf broken-echo; do
	assert_unaffected_by "$RM_HOOK" 'rm -rf hook' "$stub" 'rm -rf /tmp/scratch' 2
	assert_unaffected_by "$RM_HOOK" 'rm -rf hook' "$stub" 'ls -la' 0
	assert_unaffected_by "$CLEAN_HOOK" 'git clean hook' "$stub" 'git clean -fd' 2
	assert_unaffected_by "$CLEAN_HOOK" 'git clean hook' "$stub" 'git clean -n' 0
	assert_unaffected_by "$MASK_HOOK" 'masked exit hook' "$stub" 'just ci | tail' 2
	assert_unaffected_by "$MASK_HOOK" 'masked exit hook' "$stub" 'just ci' 0
	assert_unaffected_by "$PUSH_HOOK" 'push-to-main hook' "$stub" 'git push origin main' 2
	assert_unaffected_by "$PUSH_HOOK" 'push-to-main hook' "$stub" 'git push origin feat/x' 0
	assert_unaffected_by "$RG_HOOK" 'rg -r hook' "$stub" 'rg -r foo src/' 2
	assert_unaffected_by "$RG_HOOK" 'rg -r hook' "$stub" 'rg -n foo src/' 0
done

# The floor, over every hook in the array rather than the five this file names — so a hook
# added later is covered before anyone remembers to name it here.
#
# Be precise about what each column proves, because the empty-PATH one proves less than it
# looks like it does. With no PATH the *first* helper a body reaches fails, and for all five
# that is the jq call that reads the tool input; a body that guards jq and nothing else
# passes this assertion while still failing open on grep — the exact issue #139 defect. It is
# a floor, not the property. The broken-jq and broken-grep columns beside it are what reach
# past the first helper.
#
# broken-grep asserts an assumption worth stating: every hook in this array reaches grep
# unconditionally, so a broken grep must stop all of them whatever the payload. A future hook
# that calls grep only inside a branch would fail here legitimately, and the right response is
# to give it its own assertion with a payload that reaches its grep — not to drop the column.
hook_count=0
while IFS= read -r body; do
	[[ -n $body ]] || continue
	hook_count=$((hook_count + 1))
	assert_fails_closed_without_path "$body" "PreToolUse hook $hook_count" 'git status'
	assert_fails_closed "$body" "PreToolUse hook $hook_count" missing-jq 'git status' 'jq missing or failed'
	assert_fails_closed "$body" "PreToolUse hook $hook_count" broken-jq 'git status' 'jq missing or failed'
	assert_fails_closed "$body" "PreToolUse hook $hook_count" broken-grep 'git status' 'grep exited'
	# Input the hook cannot read a command out of, which is the same failure as a helper it
	# cannot run: `jq -r` prints the string "null" for an absent field and exits 0, so
	# without -e each guard matched its patterns against the literal text "null", found
	# nothing, and permitted the call. Malformed JSON was already covered — jq fails to
	# parse and the || fires — so these three are the cases that were not.
	assert_payload_fails_closed "$body" "PreToolUse hook $hook_count" \
		'{"tool_input":{}}' 'a payload with no command field'
	assert_payload_fails_closed "$body" "PreToolUse hook $hook_count" \
		'{}' 'a payload with no tool_input'
	assert_payload_fails_closed "$body" "PreToolUse hook $hook_count" \
		'' 'empty stdin'
	assert_payload_fails_closed "$body" "PreToolUse hook $hook_count" \
		'not json' 'a payload that is not JSON'
	# A command that is genuinely the empty string is readable and runs nothing, so it is
	# allowed. This is the line that keeps the four above from being satisfied by a hook
	# that simply refuses everything.
	assert_payload_allowed "$body" "PreToolUse hook $hook_count" \
		'{"tool_input":{"command":""}}' 'an empty command'
done < <(all_hook_commands)
# A miscount here means the enumeration silently matched nothing and the loop above asserted
# nothing — the failure mode of every gate that iterates over a query result.
((hook_count >= 5)) ||
	fail "expected at least 5 PreToolUse command hooks, enumerated $hook_count"

# The shell Claude Code runs a hook body in is not this suite's to choose, so all five hook
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
	# The degraded paths, under the same shell. hgrep exits the shell from three call shapes
	# and each is checked: the `&&` chain in the rm -rf guard, the plain `if` in the git clean
	# guard, and the `||`-tested call in the masked-exit guard's pipefail branch. A function
	# that exits from inside a compound command is where a shell difference would show up.
	assert_posix_fails_closed "$RM_HOOK" 'rm -rf hook' broken-grep 'rm -rf /tmp/scratch' 'grep exited'
	assert_posix_fails_closed "$CLEAN_HOOK" 'git clean hook' broken-grep 'git clean -fd' 'grep exited'
	assert_posix_fails_closed "$MASK_HOOK" 'masked exit hook' broken-grep 'just ci | tail' 'grep exited'
	assert_posix_fails_closed "$PUSH_HOOK" 'push-to-main hook' broken-grep \
		'git push origin main' 'grep exited'
	assert_posix_fails_closed "$RG_HOOK" 'rg -r hook' broken-grep 'rg -r foo src/' 'grep exited'
	assert_posix_fails_closed "$CLEAN_HOOK" 'git clean hook' missing-jq 'git clean -fd' 'jq missing or failed'
	# The awk branch reached only under sh: a broken awk must still refuse rather than crash
	# through, and must leave a command that matches no masking pattern alone.
	assert_posix_fails_closed "$MASK_HOOK" 'masked exit hook' broken-awk \
		'set -o pipefail; just ci | tail -50' 'awk exited'
	assert_posix_agrees "$MASK_HOOK" 'masked exit hook' 'set -o pipefail; just ci | tail -50' 0
	posix_verdict="POSIX assertions ran under $POSIX_SHELL"
fi

printf 'claude-settings-hooks-test: ok (%s)\n' "$posix_verdict"
