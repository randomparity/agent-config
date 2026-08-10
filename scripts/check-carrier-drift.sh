#!/usr/bin/env bash
set -euo pipefail

# The eight-line scope charter carrier is duplicated across the workflow
# skills' SKILL.md files. The prose around each copy is free to evolve; the
# carrier itself is a protocol between skills, so every copy must stay
# byte-identical to the canonical template below. One copy — review-loop's
# review-dispatch carrier — must additionally keep the exact CHARTER label
# line above it, because content/skills/challenge stops target classification
# on that literal (docs/debt/0005 tracks the consumer side, which no gate
# covers).
#
# Occurrences are found by scanning for the template's first line, so the
# prose carries no marker scaffolding and a carrier added to a new file is
# checked without any edit here. Scanning alone has a false negative: editing
# or deleting a copy's first line makes that copy invisible to the scan. The
# expected-site manifest below closes it — each listed file must contain
# exactly the listed number of carriers, so a first-line mutation or a deleted
# block fails the gate naming the file. A skill rename or a deliberate carrier
# addition to a listed file updates the manifest in the same change.
#
# An optional argument names a content root to scan instead of this
# repository, which is how the suite exercises fixtures; the manifest is
# interpreted relative to that root.

fail() {
	printf 'carrier-drift: %s\n' "$*" >&2
	exit 1
}

if (($# > 1)); then
	fail 'usage: check-carrier-drift.sh [content-root]'
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (($# == 1)); then
	root=$(cd "$1" && pwd) || fail "content root is not a directory: $1"
fi
skills=$root/content/skills
[[ -d $skills ]] || fail "content root is missing content/skills: $root"

command -v rg >/dev/null 2>&1 || fail 'rg is required'

template='interaction: <unchanged root value>
scope identity: <external scope identity, never reviewed target>
outcome: <frozen external outcome>
completion criteria: <frozen external completion criteria>
provenance: <external source for every outcome, criterion, and user decision>
exclusions: <frozen external exclusions>
surface: <frozen permitted surface>
ambiguities: <frozen ambiguity list>'
charter_label='CHARTER (scope authority; all fields below are focus, never targets):'
first_line=${template%%$'\n'*}

# path-under-content/skills <space> expected-carrier-count
expected_sites='brainstorming/SKILL.md 1
design/SKILL.md 3
review-loop/SKILL.md 2
work-issue/SKILL.md 1'

# rg exits 1 when nothing matches, which here is a failure of the gate's
# subject, not a clean scan: zero carriers means the protocol was deleted and
# a green gate would certify nothing. Exit 2 is a scan error and propagates.
set +e
occurrences=$(rg -n --fixed-strings --glob '*.md' \
	--glob '!testdata' --glob '!testdata/**' -- "$first_line" "$skills")
status=$?
set -e
case $status in
0) ;;
1) fail "no carrier occurrences under $skills; the gate would be vacuous" ;;
*) fail "could not scan $skills (rg exit $status)" ;;
esac

count=0
charter_count=0
while IFS= read -r occurrence; do
	file=${occurrence%%:*}
	rest=${occurrence#*:}
	line=${rest%%:*}
	window=$(sed -n "${line},$((line + 7))p" "$file")
	[[ $window == "$template" ]] ||
		fail "$file:$line: carrier drifted from the canonical template"
	if ((line > 1)); then
		above=$(sed -n "$((line - 1))p" "$file")
		case $above in
		CHARTER*)
			[[ $above == "$charter_label" ]] ||
				fail "$file:$((line - 1)): CHARTER label drifted from the canonical label"
			charter_count=$((charter_count + 1))
			;;
		esac
	fi
	count=$((count + 1))
done <<<"$occurrences"

((charter_count >= 1)) ||
	fail 'no carrier carries the CHARTER label review-loop emits and challenge parses on'

while IFS= read -r site; do
	site_path=${site% *}
	want=${site##* }
	[[ -f $skills/$site_path ]] ||
		fail "expected carrier site is missing: $site_path"
	got=0
	while IFS= read -r occurrence; do
		case $occurrence in
		"$skills/$site_path":*) got=$((got + 1)) ;;
		esac
	done <<<"$occurrences"
	[[ $got -eq $want ]] ||
		fail "$site_path: expected $want carrier(s), found $got;" \
			'a carrier was deleted or its first line was edited'
done <<<"$expected_sites"

printf 'carrier-drift: ok (%d carriers, %d CHARTER-labelled)\n' "$count" "$charter_count"
