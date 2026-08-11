#!/usr/bin/env bash
set -euo pipefail

# `install_managed_path` ends in `cp -pR`, so a call whose source is a directory
# ships that whole subtree into the agent's configuration directory verbatim.
# Three of those trees hold files that are deployed content in their own right,
# and nothing else counts their entries: check-shared-standards.sh names one file
# inside the rules tree, and check-deployed-references.sh scans these trees for
# what a deployed file may say. So a file dropped into one of them reaches every
# user's global configuration with no gate asking whether it belongs, which is
# the residual ADR 0041 disclosed and this gate closes.
#
# The manifest is the answer to "should this be deployed", and it is source: this
# gate cannot defend against edits to itself. Narrowing it is only mostly caught
# -- a deleted member line is red, because the file it named is then undeclared,
# and a deleted tree line with its members fails the suite's summary assertion.
# What survives is a coordinated edit to this script's lists and the suite's
# (ADR 0045).
#
# An optional argument names a repository root to check instead of this one,
# which is how the suite points the checker at a fixture.

# Pinned for the whole run, not per-sort. `comm` collates by locale too, so
# C-sorted inputs read back under another locale make it emit spurious lines and
# `not in sorted order` diagnostics -- a green run that is wrong and noisy. One
# export keeps the caller's environment out of the verdict entirely.
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if (($# > 1)); then
	printf 'usage: %s [repository-root]\n' "${0##*/}" >&2
	exit 2
fi

if (($# == 1)); then
	# Not `cd || exit`: an unreadable or misspelled root is a fault, and every
	# other fault here exits 2. Letting errexit take it would exit 1, the status
	# that means this gate found a difference.
	if ! ROOT="$(cd "$1" 2>/dev/null && pwd)"; then
		printf 'deployed-membership: repository root is not a directory: %s\n' "$1" >&2
		exit 2
	fi
fi

# Every tree the installer copies whole whose members are deployed content in
# their own right. `content/skills` is deliberately absent: its unit of delivery
# is the skill directory, check-skill-layout.sh gates that unit's shape, and a
# per-file manifest there would churn on ordinary work (ADR 0045).
trees='agents/bob/shared/rules
content/languages
content/references'

# Every file those trees may contain. A line here is the deliberate act of
# deploying a file to every user; adding one without it fails this gate.
manifest='agents/bob/shared/rules/global-development-standards.md
content/languages/bash.md
content/languages/github-actions.md
content/languages/python.md
content/languages/rust.md
content/languages/typescript.md
content/references/orchestration.md'

# Both halves keep the environment out of the exit code. An unwritable TMPDIR
# would otherwise let errexit propagate mktemp's status 1 -- the status this gate
# reserves for a membership difference -- with no finding printed; and under
# set -e a failing command inside an EXIT trap replaces the exiting status, so an
# undeletable workspace would turn a green run's exit 0 into a 1 after stdout had
# already said ok.
if ! workspace="$(mktemp -d "${TMPDIR:-/tmp}/deployed-membership.XXXXXX")"; then
	printf 'deployed-membership: could not create a workspace\n' >&2
	exit 2
fi
trap 'rm -R "$workspace" 2>/dev/null || :' EXIT

result_status=0

report() { # class relative-path
	printf 'deployed-membership: %s: %s\n' "$1" "$2" >&2
	result_status=1
}

# `-d` alone would be wrong: test -d dereferences, so a tree replaced by a
# symlink to a directory would survive it and find would then print the tree path
# itself as a non-directory entry -- a finding naming a path the manifest can
# never hold. A tree that is absent, a regular file, or a symlink contributes no
# members instead, and its declared files report as missing below. That is the
# no-fault-for-a-missing-tree decision: two of these trees hold exactly one file
# and Git does not track empty directories, so deleting that file removes the
# directory from every fresh checkout, and a fault would tell CI the gate could
# not run about the very deletion it exists to describe.
surviving=()
while IFS= read -r tree; do
	if [[ -d "$ROOT/$tree" && ! -L "$ROOT/$tree" ]]; then
		surviving+=("$ROOT/$tree")
	fi
done <<<"$trees"

# find is used in place of the repository's usual rg because it is total by
# construction: no ignore file and no RIPGREP_CONFIG_PATH can subtract a path
# from it. That matters beyond a dirty working tree -- ripgrep applies
# .gitignore to tracked files too, so a tracked file the repository also ignores
# ships under cp -pR and is invisible to a default ripgrep scan, in CI as much as
# locally.
#
# The guard is not decoration. GNU find given no path operand defaults to `.` and
# would report every file under the current directory as an unexpected member,
# while BSD find on the macos-latest leg errors instead -- two different wrong
# answers from one unstated case. Trees are passed without a trailing slash,
# which would force find to dereference the argument.
#
# The status is captured directly rather than through a pipeline, so a scan that
# did not happen cannot read as an empty one. Enumeration completes before any
# comparison, so this fault can never suppress a finding already made.
: >"$workspace/absolute"
if ((${#surviving[@]} > 0)); then
	if ! find "${surviving[@]}" ! -type d -print0 >"$workspace/absolute"; then
		printf 'deployed-membership: could not enumerate the installed trees\n' >&2
		exit 2
	fi
fi

# A member that is not a regular file is a finding whatever the manifest says,
# and is still a member for the comparison -- so a declared symlink reports
# non-regular-member alone rather than also reporting as missing. `-f` follows a
# symlink to a file, hence the explicit `-L` test beside it.
: >"$workspace/present-unsorted"
: >"$workspace/non-regular-unsorted"
while IFS= read -r -d '' absolute; do
	relative="${absolute#"$ROOT/"}"
	# The comparison below is line-delimited, so a path holding a newline would
	# split into two records -- and if both halves happened to equal declared
	# entries, the undeclared file would vanish from the comparison and the gate
	# would print ok over a file cp -pR still ships. Refusing the path outright
	# is the only answer that cannot be wrong; the path is not echoed, because a
	# newline in a diagnostic is how it would be misread in the first place.
	case "$relative" in
	*$'\n'*)
		printf 'deployed-membership: a member path contains a newline and cannot be compared\n' >&2
		exit 2
		;;
	esac
	printf '%s\n' "$relative" >>"$workspace/present-unsorted"
	if [[ ! -f "$absolute" || -L "$absolute" ]]; then
		printf '%s\n' "$relative" >>"$workspace/non-regular-unsorted"
	fi
done <"$workspace/absolute"

# `sort -u` is what makes a manifest line duplicated by a careless edit inert:
# the duplicate collapses before any comparison, so it can never surface as a
# missing-member for a file that is plainly there. Bash associative arrays would
# say this more directly and are unavailable -- declare -A is Bash 4.0+ and the
# macos-latest leg runs system Bash 3.2.
# `-o` ahead of the operand, not after it: an option following a file operand is
# only reordered by a getopt that permutes argv, so `sort -u FILE -o OUT` reads
# `-o` and `OUT` as two more input files wherever it does not -- under an exported
# POSIXLY_CORRECT, and potentially on the BSD userland of the macos leg. The
# environment must not reach this verdict.
sort -u -o "$workspace/present" "$workspace/present-unsorted"
sort -u -o "$workspace/non-regular" "$workspace/non-regular-unsorted"
printf '%s\n' "$manifest" | sort -u >"$workspace/declared"

comm -23 "$workspace/present" "$workspace/declared" >"$workspace/unexpected"
comm -13 "$workspace/present" "$workspace/declared" >"$workspace/missing"

# Every finding before the run exits, not the first one: a branch that adds a
# file and deletes another has to be told about both rather than sent round the
# loop twice. The order is fixed so the suite can assert it.
unexpected_reported=0
while IFS= read -r relative; do
	report unexpected-member "$relative"
	unexpected_reported=1
done <"$workspace/unexpected"

while IFS= read -r relative; do
	report non-regular-member "$relative"
done <"$workspace/non-regular"

while IFS= read -r relative; do
	report missing-member "$relative"
done <"$workspace/missing"

# Last, after every finding, so the fixed emission order above is untouched.
# Named at all because this class has two responses that are opposite in effect
# and only one is right: deleting the file is correct, while adding a manifest
# line is also green and would declare a merge artefact or a scratch draft as
# content that installs for every user. The other two classes have unambiguous
# remedies and get no such line.
if ((unexpected_reported == 1)); then
	printf 'deployed-membership: delete an unexpected member, or declare it here only if it is meant to install for every user\n' >&2
fi

if ((result_status == 0)); then
	printf 'deployed-membership: ok (%s declared members across %s installed trees)\n' \
		"$(wc -l <"$workspace/declared" | tr -d '[:space:]')" \
		"${#surviving[@]}"
fi

exit "$result_status"
