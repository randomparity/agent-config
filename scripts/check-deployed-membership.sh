#!/usr/bin/env bash
set -euo pipefail

# `install_managed_path` ends in `cp -pR`, so a call whose source is a directory
# ships that whole subtree into the agent's configuration directory verbatim.
# Four of those trees reach a user, and nothing else counts their entries:
# check-shared-standards.sh names one file inside the rules tree, and
# check-deployed-references.sh scans these trees for what a deployed file may say.
# So an entry dropped into one of them reaches every user's global configuration
# with no gate asking whether it belongs, which is the residual ADR 0041 disclosed
# and this gate closes.
#
# The gate compares each tree at the granularity that tree's unit of delivery has.
# Three of them deploy files, so their members are files (ADR 0045). The fourth,
# `content/skills`, deploys skill directories, so its members are the tree's
# top-level children (ADR 0054). One comparison, two enumerators; the two halves
# share the workspace, the `fault` helper and the collation pin below, and keep
# their own finding vocabulary so a reader can tell which one spoke.
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

# Every tree the installer copies whole whose members are deployed *files* in their
# own right. `content/skills` is not among them because its members are
# directories, not because it is ungated: it is declared below (ADR 0054). A
# per-file manifest there would churn on ordinary work, which is the cost argument
# ADR 0045 made and this script still honours.
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

# The tree whose unit of delivery is the directory. Its top-level children are the
# members; what is inside one is deliberately ungated, and check-skill-layout.sh
# owns their shape (ADR 0054).
skills_tree='content/skills'

# Every skill directory that tree may contain. A line here is the deliberate act of
# deploying a complete instruction set to every user; adding a directory without one
# fails this gate. Two commits in this repository's history ever added one, so the
# churn objection that keeps the files inside them undeclared does not reach this
# list.
skill_directories='brainstorming
build-tdd
campaign
challenge
clean-branches
codex-fleet
compound
decision-records
design
epic
executing-plans
finishing-a-development-branch
github-tracking
groom
issue
merge-cleanup
merge-dependabot
preflight
receiving-code-review
recover-orphans
requesting-code-review
retro
review-loop
scope
scope-audit
ship-pr
simplify-changes
subagent-driven-development
systematic-debugging
test-driven-development
threat-scan
triage-issues
using-git-worktrees
verification-before-completion
work-issue
writing-plans'

# Exit 1 means this gate found a difference. Nothing about the environment may
# borrow that status, so every step that can fail for a reason other than the
# comparison routes through here instead of letting errexit propagate a 1 -- and
# with it a bare diagnostic from whichever tool failed, carrying no
# `deployed-membership:` line for the operator to act on.
fault() { # message
	printf 'deployed-membership: %s\n' "$*" >&2
	exit 2
}

# An unwritable TMPDIR would otherwise let errexit propagate mktemp's status 1;
# and under set -e a failing command inside an EXIT trap replaces the exiting
# status, so an undeletable workspace would turn a green run's exit 0 into a 1
# after stdout had already said ok.
workspace="$(mktemp -d "${TMPDIR:-/tmp}/deployed-membership.XXXXXX")" ||
	fault 'could not create a workspace'
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
: >"$workspace/absolute" || fault 'could not write to the workspace'
if ((${#surviving[@]} > 0)); then
	find "${surviving[@]}" ! -type d -print0 >"$workspace/absolute" ||
		fault 'could not enumerate the installed trees'
fi

# A member that is not a regular file is a finding whatever the manifest says,
# and is still a member for the comparison -- so a declared symlink reports
# non-regular-member alone rather than also reporting as missing. `-f` follows a
# symlink to a file, hence the explicit `-L` test beside it.
: >"$workspace/present-unsorted" || fault 'could not write to the workspace'
: >"$workspace/non-regular-unsorted" || fault 'could not write to the workspace'
while IFS= read -r -d '' absolute; do
	relative="${absolute#"$ROOT/"}"
	# The comparison below is line-delimited, so a path holding a newline would
	# split into two records -- and if both halves happened to equal declared
	# entries, the undeclared file would vanish from the comparison and the gate
	# would print ok over a file cp -pR still ships. Refusing the path outright
	# is the only answer that cannot be wrong; the path is not echoed, because a
	# newline in a diagnostic is how it would be misread in the first place.
	case "$relative" in
	*$'\n'*) fault 'a member path contains a newline and cannot be compared' ;;
	esac
	printf '%s\n' "$relative" >>"$workspace/present-unsorted" ||
		fault 'could not write to the workspace'
	if [[ ! -f "$absolute" || -L "$absolute" ]]; then
		printf '%s\n' "$relative" >>"$workspace/non-regular-unsorted" ||
			fault 'could not write to the workspace'
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
# Each of these routes failure to `fault` for the same reason the mktemp guard
# does. GNU sort happens to exit 2 on error and comm exits 1, so leaving them
# bare would make the gate's status depend on which implementation ran rather
# than on what it found -- a full disk mid-run would report a membership
# difference. The guard is construction; the exit codes are not ours to rely on.
sort -u -o "$workspace/present" "$workspace/present-unsorted" ||
	fault 'could not sort the enumerated members'
sort -u -o "$workspace/non-regular" "$workspace/non-regular-unsorted" ||
	fault 'could not sort the enumerated members'
printf '%s\n' "$manifest" | sort -u >"$workspace/declared" ||
	fault 'could not sort the manifest'

comm -23 "$workspace/present" "$workspace/declared" >"$workspace/unexpected" ||
	fault 'could not compare the enumerated members against the manifest'
comm -13 "$workspace/present" "$workspace/declared" >"$workspace/missing" ||
	fault 'could not compare the enumerated members against the manifest'

# The skills tree gets the same `-d` and not `-L` filter, for the same reason: a tree
# replaced by a symlink to a directory would otherwise be walked and its target's
# children reported as this repository's. A tree that does not survive contributes no
# entries, so every declared directory reports as missing -- the same
# no-fault-for-a-missing-tree answer the three trees get.
# `-mindepth 1 -maxdepth 1` excludes the root by depth. The two ways of excluding it
# by pattern both have a case where the match fails, `find` then prints the tree root
# and descends no further, and this gate reports the tree itself as an unexpected entry
# beside every declared name as missing -- a total false red. `! -path "$root"` matches
# by fnmatch, so a checkout path holding a well-formed bracket expression does not match
# itself. `! -name .` fails on the platform this repository gates: BSD find sets a start
# point's `fts_name` to the whole operand rather than its basename, so the macos-latest
# leg would prune at the root. Depth matches no pattern at all.
# The survival filter is inline because there is one tree here, not a list: `-d` and not
# `-L`, as above. The `! -L` leg is defensive rather than load-bearing at this
# granularity -- `find` does not follow a symlink operand, so with `-mindepth 1` a tree
# replaced by a symlink enumerates empty whether it survives the filter or not. It is
# kept for symmetry with the filter above, where the leg decides the answer, and no
# suite row can distinguish it.
: >"$workspace/skill-absolute" || fault 'could not write to the workspace'
if [[ -d "$ROOT/$skills_tree" && ! -L "$ROOT/$skills_tree" ]]; then
	find "$ROOT/$skills_tree" -mindepth 1 -maxdepth 1 -print0 >"$workspace/skill-absolute" ||
		fault 'could not enumerate the skills tree'
fi

# Every child is a member whatever its type, so a stray file at the top level is
# reported as the undeclared entry it is. A child that is not a directory is
# additionally a finding whatever the list says: `cp -pR` preserves a symlink and
# `find -mindepth 1` does not descend one, so a declared name resolving to a link would
# deploy whatever its target resolves to on the user's machine -- an unbounded subtree
# admitted by one declaration. That is `non-regular-member`'s argument at this
# granularity, and check-skill-layout.sh refusing the same entry does not make it this
# gate's to skip.
: >"$workspace/skill-present-unsorted" || fault 'could not write to the workspace'
: >"$workspace/skill-non-directory-unsorted" || fault 'could not write to the workspace'
while IFS= read -r -d '' absolute; do
	name="${absolute##*/}"
	# Refused rather than reported, for the reason the member paths are: both halves of
	# a split name can equal declared entries, `sort -u` then collapses them, and the
	# undeclared directory vanishes from the comparison while `cp -pR` still ships it.
	# The name is not echoed -- a newline in a diagnostic is how it would be misread.
	case "$name" in
	*$'\n'*) fault 'a skill directory name contains a newline and cannot be compared' ;;
	esac
	printf '%s\n' "$name" >>"$workspace/skill-present-unsorted" ||
		fault 'could not write to the workspace'
	if [[ ! -d "$absolute" || -L "$absolute" ]]; then
		printf '%s\n' "$name" >>"$workspace/skill-non-directory-unsorted" ||
			fault 'could not write to the workspace'
	fi
done <"$workspace/skill-absolute"

# The non-directory list is sorted too. It is built from `find` output, which is readdir
# order, so without this its block would emit in whatever order the filesystem gave. No
# fixture can prove that portably -- tmpfs, ext4 with dir_index and APFS each answer
# differently -- so the sort is defensive and rests on being read.
#
# The two sorts are told apart in their messages for the reason the three-tree half tells
# `could not sort the enumerated members` from `could not sort the manifest`: a full disk
# during one must not report the other. The comparison messages name the skills tree for
# the same reason, so an operator can tell which half faulted.
sort -u -o "$workspace/skill-present" "$workspace/skill-present-unsorted" ||
	fault 'could not sort the enumerated skill directories'
sort -u -o "$workspace/skill-non-directory" "$workspace/skill-non-directory-unsorted" ||
	fault 'could not sort the enumerated skill directories'
printf '%s\n' "$skill_directories" | sort -u >"$workspace/skill-declared" ||
	fault 'could not sort the declared skill directories'

comm -23 "$workspace/skill-present" "$workspace/skill-declared" \
	>"$workspace/skill-unexpected" ||
	fault 'could not compare the enumerated skill directories against the declared set'
comm -13 "$workspace/skill-present" "$workspace/skill-declared" \
	>"$workspace/skill-missing" ||
	fault 'could not compare the enumerated skill directories against the declared set'

# Every finding before the run exits, not the first one: a branch that adds a
# file and deletes another has to be told about both rather than sent round the
# loop twice. The order is fixed so the suite can assert it.
while IFS= read -r relative; do
	report unexpected-member "$relative"
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
if [[ -s "$workspace/unexpected" ]]; then
	printf 'deployed-membership: delete an unexpected member, or declare it here only if it is meant to install for every user\n' >&2
fi

# The skills block comes whole after the file block and its remedy, rather than
# interleaving the two rules' classes. That is what keeps every expected sequence the
# suite already pinned for the three trees asserting the same bytes.
while IFS= read -r name; do
	report unexpected-skill-entry "$skills_tree/$name"
done <"$workspace/skill-unexpected"

while IFS= read -r name; do
	report non-directory-skill-entry "$skills_tree/$name"
done <"$workspace/skill-non-directory"

while IFS= read -r name; do
	report missing-skill-directory "$skills_tree/$name"
done <"$workspace/skill-missing"

# Its own remedy line, not the one above. That one says "member", the two blocks fire
# independently, and a reader handed the other block's remedy has to work out which
# finding it addresses. The hazard is the same: deleting the entry is correct, and
# declaring it is also green while shipping a whole instruction set to every user.
if [[ -s "$workspace/skill-unexpected" ]]; then
	printf 'deployed-membership: delete an unexpected entry, or declare it here only if it is a skill meant to install for every user\n' >&2
fi

if ((result_status == 0)); then
	# Both granularities, because the gate now answers at two and a reader who saw only
	# the member count would take it for the whole deployment. The tree is named because
	# it is a fourth installed tree, and the counts mean different things: the tree count
	# is of *surviving* trees and drops when one is absent, while the directory count is
	# of declared names and never does. The skills tree is deliberately not folded into
	# `surviving`.
	printf 'deployed-membership: ok (%s declared members across %s installed trees, %s declared skill directories in %s)\n' \
		"$(wc -l <"$workspace/declared" | tr -d '[:space:]')" \
		"${#surviving[@]}" \
		"$(wc -l <"$workspace/skill-declared" | tr -d '[:space:]')" \
		"$skills_tree"
fi

exit "$result_status"
