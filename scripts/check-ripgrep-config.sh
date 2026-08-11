#!/usr/bin/env bash
set -euo pipefail

# Fails when a tracked shell source runs ripgrep while RIPGREP_CONFIG_PATH can
# still reach it. ripgrep applies that file's contents as arguments ahead of the
# ones a caller passes, so every flag a call does not set is chosen by whoever
# set the variable -- and the gates in the verify chain decide their verdict from
# ripgrep's output. `--fixed-strings` in a personal ripgreprc turned the secret
# scanner into a scan that matches nothing and exits 0 (record 0051).
#
# Two forms neutralise it and this gate accepts either, because both leave
# ripgrep unable to read a config file and requiring one form would force an edit
# into files another change owns:
#
#   - `unset RIPGREP_CONFIG_PATH` alone on a line at column 0, which covers every
#     ripgrep the source runs including one added later; or
#   - `--no-config` on every line that invokes ripgrep.
#
# Sources are discovered, never listed (list-shell-sources.sh), so a new script
# is covered with no edit here. There is no exemption list: a file that never
# runs ripgrep produces no invocation and is never asked for the statement.
#
# Exit 0 clean, 1 on a finding naming file:line, 2 on a fault.

fault() {
	printf 'ripgrep-config: %s\n' "$*" >&2
	exit 2
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (($# > 1)); then
	fault 'usage: check-ripgrep-config.sh [repository-root]'
fi
if (($# == 1)); then
	root=$(cd "$1" 2>/dev/null && pwd) || fault "repository root is not a directory: $1"
fi

lister="$root/scripts/list-shell-sources.sh"
[[ -x $lister ]] || fault "source lister is missing or not executable: $lister"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/ripgrep-config.XXXXXX") || fault 'could not create a scratch directory'
cleanup() {
	case $scratch in
	"${TMPDIR:-/tmp}"/ripgrep-config.*) rm -R -- "$scratch" ;;
	*) printf 'ripgrep-config: refusing cleanup outside scratch root: %s\n' "$scratch" >&2 ;;
	esac
}
trap cleanup EXIT

# The list is captured to a file rather than read from a process substitution:
# `while ... done < <(lister)` reports the loop's status, not the lister's, so a
# discovery that failed halfway would yield a short list and a green gate. That
# is the same shape of silent miss this gate exists to prevent.
if ! (cd "$root" && "$lister" --all -z) >"$scratch/sources"; then
	fault 'could not discover shell sources'
fi

# read -d '' keeps the NUL-delimited list intact and works on bash 3.2, which is
# the macOS system shell this repository still supports; mapfile does not.
sources=()
while IFS= read -r -d '' source; do
	sources+=("$source")
done <"$scratch/sources"

((${#sources[@]} > 0)) || fault 'no shell sources discovered'

for source in "${sources[@]}"; do
	[[ -r "$root/$source" ]] || fault "source is unreadable: $source"
done

# The scanner reads shell text, so it strips before it matches: a ripgrep
# *mentioned* in a comment, a quoted string or a here-document body is not one
# the file runs. Both mentions in the tree today are of that kind --
# claude-settings-hooks-test.sh embeds `just ci | rg -n error` as hook fixture
# data, and check-carrier-drift.sh writes "(rg exit $status)" in a message -- and
# a gate that flagged either would be answered by an exemption list, which is the
# thing that rots.
#
# It models quoting, comments, line continuations and here-documents; it is not a
# shell parser and does not claim to be. A construct it misreads produces a
# finding on a compliant file, which is loud, rather than silence on an exposed
# one. It does not check that the flags a call passes are the right ones -- that
# is each gate's own suite.
findings=$(
	cd "$root" && awk '
	function strip(s,   i, c, out, quote, n) {
		out = ""
		quote = ""
		n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 1)
			if (quote == "\047") {
				if (c == "\047") quote = ""
				continue
			}
			if (quote == "\"") {
				if (c == "\\") { i++; continue }
				if (c == "\"") quote = ""
				continue
			}
			if (c == "\\") { i++; out = out "@"; continue }
			if (c == "\047" || c == "\"") { quote = c; out = out "@"; continue }
			# A # opens a comment only where a word could not continue.
			if (c == "#" && (out == "" || substr(out, length(out), 1) ~ /[ \t;|&(){}]/)) break
			out = out c
		}
		return out
	}

	# The separators after which a word is a command name. $( and <( reduce to (
	# and && / || to &, so one character class covers them all.
	function runs_ripgrep(s,   n, i, parts, seg) {
		gsub(/[;|&(){}]/, "\n", s)
		n = split(s, parts, "\n")
		for (i = 1; i <= n; i++) {
			seg = parts[i]
			sub(/^[ \t]+/, "", seg)
			while (1) {
				if (seg ~ /^(if|then|else|elif|while|until|do|time|command|exec|!)[ \t]+/) {
					sub(/^[^ \t]+[ \t]+/, "", seg)
					continue
				}
				if (seg ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) {
					sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", seg)
					continue
				}
				break
			}
			if (seg ~ /^rg([ \t]|$)/) return 1
		}
		return 0
	}

	# The word a here-document ends on, or "" when the line opens none. <<< is a
	# here-string and reads no body.
	function heredoc_word(s,   rest, word) {
		while (match(s, /<</)) {
			rest = substr(s, RSTART + 2)
			s = rest
			if (substr(rest, 1, 1) == "<") continue
			sub(/^-/, "", rest)
			sub(/^[ \t]+/, "", rest)
			if (match(rest, /^("[^"]+"|\047[^\047]+\047|[A-Za-z_][A-Za-z0-9_]*)/)) {
				word = substr(rest, RSTART, RLENGTH)
				gsub(/["\047]/, "", word)
				return word
			}
		}
		return ""
	}

	FNR == 1 {
		neutralised[FILENAME] = 0
		pending = ""
		start = 0
		terminator = ""
	}

	terminator != "" {
		line = $0
		sub(/^\t+/, "", line)
		if ($0 == terminator || line == terminator) terminator = ""
		next
	}

	{
		# `unset RIPGREP_CONFIG_PATH` is required alone at column 0: that is what
		# makes it file scope rather than a statement inside a branch that may
		# never run, and it keeps the check answerable without tracking blocks.
		if ($0 ~ /^unset[ \t]+RIPGREP_CONFIG_PATH[ \t]*(#.*)?$/) neutralised[FILENAME] = 1

		if (pending == "") start = FNR
		pending = pending $0
		# An odd number of trailing backslashes continues the logical line.
		if (match(pending, /\\+$/) && RLENGTH % 2 == 1) {
			pending = substr(pending, 1, length(pending) - 1)
			next
		}

		terminator = heredoc_word(pending)
		stripped = strip(pending)
		if (runs_ripgrep(stripped) && stripped !~ /--no-config/) {
			invocations[FILENAME] = invocations[FILENAME] start "\n"
		}
		pending = ""
	}

	END {
		for (file in invocations) {
			if (neutralised[file]) continue
			n = split(invocations[file], lines, "\n")
			for (i = 1; i <= n; i++) {
				if (lines[i] != "") printf "%s:%s\n", file, lines[i]
			}
		}
	}
	' "${sources[@]}" | sort -t: -k1,1 -k2,2n
) || fault 'could not scan the shell sources'

if [[ -n $findings ]]; then
	while IFS= read -r finding; do
		printf 'ripgrep-config: %s: runs rg without unset RIPGREP_CONFIG_PATH or --no-config\n' \
			"$finding" >&2
	done <<<"$findings"
	printf 'ripgrep-config: a config file may steer these scans; see docs/adr/0051-gate-scripts-neutralise-the-ripgrep-config.md\n' >&2
	exit 1
fi

printf 'ripgrep-config: ok (%s shell sources)\n' "${#sources[@]}"
