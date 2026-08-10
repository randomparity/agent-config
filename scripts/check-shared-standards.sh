#!/usr/bin/env bash
set -euo pipefail

# The shared guardrail rule sets are one Markdown block, delimited by an HTML
# comment pair, duplicated into every deployed instruction file. The prose
# around each copy is agent-native and free to differ; the block states the same
# rules for every agent, so every copy must stay byte-identical to the canonical
# one under content/instructions.
#
# Detection follows check-carrier-drift.sh: a scan finds every block under the
# deployment roots, so a copy that appears in a new file is compared without an
# edit here, and an expected-site manifest closes the scan's false negative —
# deleting or mistyping a begin marker makes that copy invisible to the scan,
# and the manifest fails naming the file.
#
# The canonical block is resolved before anything else because it is the
# comparison source. When it is missing or malformed the run reports that alone:
# three drift findings measured against an empty string would bury it.
#
# An optional argument names a repository root to check instead of this one,
# which is how the suite points the checker at a fixture tree.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
	printf 'shared-standards: rg is required\n' >&2
	exit 2
fi

if (($# > 1)); then
	printf 'usage: %s [repository-root]\n' "${0##*/}" >&2
	exit 2
fi

if (($# == 1)); then
	ROOT="$(cd "$1" && pwd)"
fi

begin_marker='<!-- shared-standards:begin -->'
end_marker='<!-- shared-standards:end -->'
canonical='content/instructions/global-development-standards.md'

# Every root a block may legitimately appear under: the canonical file's
# directory and the three trees the installer deploys verbatim. A new agent tree
# is an edit here and in the manifest below, the same residual carrier-drift
# accepts for its own sites.
scan_paths=(
	"$ROOT/content/instructions"
	"$ROOT/agents/claude/shared"
	"$ROOT/agents/codex/shared"
	"$ROOT/agents/bob/shared"
)

# Every file that must hold exactly one block.
manifest="$canonical
agents/claude/shared/CLAUDE.md
agents/codex/shared/AGENTS.md
agents/bob/shared/rules/global-development-standards.md"

result_status=0

fatal() {
	printf 'shared-standards: %s\n' "$*" >&2
	exit 2
}

report() { # class relative-path [line]
	if (($# == 3)); then
		printf 'shared-standards: %s: %s:%s\n' "$1" "$2" "$3" >&2
	else
		printf 'shared-standards: %s: %s\n' "$1" "$2" >&2
	fi
	result_status=1
}

for path in "${scan_paths[@]}"; do
	if [[ ! -d "$path" ]]; then
		fatal "scan root is missing: ${path#"$ROOT/"}"
	fi
done

if [[ ! -f "$ROOT/$canonical" ]]; then
	fatal "canonical file is missing: $canonical"
fi

count_lines() { # newline-delimited-text
	if [[ -z "$1" ]]; then
		printf '0\n'
		return 0
	fi
	printf '%s\n' "$1" | wc -l | tr -d '[:space:]'
}

# Line numbers of every occurrence of one marker in one file, newline-delimited
# and empty when the file has none. rg exits 1 on no match, which is a normal
# answer here rather than a failure; anything else is a broken scan.
marker_lines() { # absolute-path marker
	local output rg_status
	set +e
	output=$(rg -n --fixed-strings -- "$2" "$1")
	rg_status=$?
	set -e
	case "$rg_status" in
	0) printf '%s\n' "$output" | sed 's/:.*//' ;;
	1) ;;
	*) fatal "could not scan $1 (rg exit $rg_status)" ;;
	esac
}

# Reads one file's block into block_body and its begin marker's line into
# block_line. Returns 1 after reporting, when the file has no well-formed block.
block_body=''
block_line=0
read_block() { # relative-path
	local relative="$1" absolute="$ROOT/$1"
	local begins ends begin_count end_count

	begins=$(marker_lines "$absolute" "$begin_marker")
	ends=$(marker_lines "$absolute" "$end_marker")
	begin_count=$(count_lines "$begins")
	end_count=$(count_lines "$ends")

	if ((begin_count == 0)); then
		report missing-block "$relative"
		return 1
	fi
	if ((begin_count > 1)); then
		report duplicate-block "$relative" "$(printf '%s\n' "$begins" | sed -n 2p)"
		return 1
	fi
	if ((end_count > 1)); then
		report duplicate-block "$relative" "$(printf '%s\n' "$ends" | sed -n 2p)"
		return 1
	fi
	if ((end_count == 0)) || ((ends < begins)); then
		report unterminated-block "$relative" "$begins"
		return 1
	fi

	block_line=$begins
	block_body=$(sed -n "$((begins + 1)),$((ends - 1))p" "$absolute")
}

if ! read_block "$canonical"; then
	exit "$result_status"
fi
canonical_body=$block_body
canonical_line=$block_line

# The fail-closed guard. Emptying the canonical block would otherwise leave
# every copy trivially identical and the gate green over nothing. It counts
# subsections and reads none of their text, which is the line ADR 0041 draws
# between gating copy identity and gating wording.
subsections=$(printf '%s\n' "$canonical_body" | grep -c '^### ' || :)
if ((subsections < 3)); then
	report canonical-shape "$canonical" "$canonical_line"
	exit "$result_status"
fi

set +e
carriers=$(rg -l --fixed-strings --hidden -- "$begin_marker" "${scan_paths[@]}")
carriers_status=$?
set -e
case "$carriers_status" in
0) ;;
1) fatal 'no shared-standards block was found; the gate would be vacuous' ;;
*) fatal "could not scan for blocks (rg exit $carriers_status)" ;;
esac

while IFS= read -r absolute; do
	relative=${absolute#"$ROOT/"}
	if [[ "$relative" == "$canonical" ]]; then
		continue
	fi
	if ! read_block "$relative"; then
		continue
	fi
	if [[ "$block_body" != "$canonical_body" ]]; then
		report block-drift "$relative" "$block_line"
	fi
done <<<"$carriers"

# The manifest sees what the scan cannot: a file whose begin marker was deleted
# or mistyped carries no block the scan can find, and only an expected site can
# report its absence.
while IFS= read -r relative; do
	if [[ ! -f "$ROOT/$relative" ]]; then
		fatal "expected block site is missing: $relative"
	fi
	case $'\n'"$carriers"$'\n' in
	*$'\n'"$ROOT/$relative"$'\n'*) continue ;;
	esac
	report missing-block "$relative"
done <<<"$manifest"

if ((result_status == 0)); then
	printf 'shared-standards: ok (%s copies match the canonical block)\n' \
		"$(count_lines "$carriers")"
fi

exit "$result_status"
