#!/usr/bin/env bash
set -euo pipefail

# Fixture suites for scripts/check-carrier-drift.sh. Each fixture is a content
# root holding content/skills/<name>/SKILL.md files — all the gate reads —
# shaped to the gate's expected-site manifest: brainstorming 1, design 3,
# review-loop 2 (one CHARTER-labelled), work-issue 1.
#
# Mutations avoid `sed -i` entirely: BSD sed requires a backup suffix there,
# and this suite runs on the macOS CI leg (ADR 0027).

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate=$script_dir/check-carrier-drift.sh
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/carrier-drift-test.XXXXXX")
trap 'rm -R "$tmp_root"' EXIT

fail() {
	printf 'carrier-drift-test: %s\n' "$*" >&2
	exit 1
}

template='interaction: <unchanged root value>
scope identity: <external scope identity, never reviewed target>
outcome: <frozen external outcome>
completion criteria: <frozen external completion criteria>
provenance: <external source for every outcome, criterion, and user decision>
exclusions: <frozen external exclusions>
surface: <frozen permitted surface>
ambiguities: <frozen ambiguity list>'
charter_label='CHARTER (scope authority; all fields below are focus, never targets):'

write_skill() { # root name body
	local root=$1 name=$2 body=$3
	mkdir -p "$root/content/skills/$name"
	printf '%s\n' "$body" >"$root/content/skills/$name/SKILL.md"
}

write_canonical_tree() { # root
	local root=$1
	write_skill "$root" brainstorming "# Brainstorming

SCOPE CHECKPOINT
$template
question: <one design-selecting question>
why design-changing: <affected scope field or normative guarantee>"
	write_skill "$root" design "# Design

$template

More prose.

$template

Even more prose.

$template"
	write_skill "$root" review-loop "# Review loop

$template

$charter_label
$template
focus: <review focus, unchanged>"
	write_skill "$root" work-issue "# Work issue

$template"
}

# Portable single-line replacement: the first line equal to $2 becomes $3.
replace_first_line() { # file old new
	local file=$1 old=$2 new=$3
	awk -v old="$old" -v new="$new" '
		!done && $0 == old { print new; done = 1; next }
		{ print }
	' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

assert_passes() { # name root
	local name=$1 root=$2 output
	if ! output=$("$gate" "$root" 2>&1); then
		fail "$name: expected pass, got: $output"
	fi
}

assert_fails() { # name root expected-fragment
	local name=$1 root=$2 expected=$3 output status=0
	output=$("$gate" "$root" 2>&1) || status=$?
	[[ $status -ne 0 ]] || fail "$name: expected failure, got pass"
	[[ $output == *"$expected"* ]] ||
		fail "$name: expected '$expected' in: $output"
}

pass_root=$tmp_root/pass
write_canonical_tree "$pass_root"
assert_passes 'canonical carriers' "$pass_root"

# A drifted field line inside one carrier of many.
drift_root=$tmp_root/drift
cp -R "$pass_root" "$drift_root"
replace_first_line "$drift_root/content/skills/work-issue/SKILL.md" \
	'surface: <frozen permitted surface>' \
	'surface: <whatever the reviewer allows>'
assert_fails 'drifted window' "$drift_root" 'carrier drifted from the canonical template'

# The CHARTER label is the parsing boundary challenge consumes; a one-sided
# rename must fail even when the eight lines below it are intact.
label_root=$tmp_root/label
cp -R "$pass_root" "$label_root"
replace_first_line "$label_root/content/skills/review-loop/SKILL.md" \
	"$charter_label" \
	'CHARTER (reviewer may restate the fields below):'
assert_fails 'drifted CHARTER label' "$label_root" 'CHARTER label drifted'

# Relocating the canonical label onto review-loop's other carrier preserves
# both carrier counts and the label's presence, but leaves the dispatch
# carrier (the one followed by the focus line) unlabelled. The gate must
# bind the label to that specific occurrence.
reloc_root=$tmp_root/reloc
write_skill "$reloc_root" brainstorming "# Brainstorming

SCOPE CHECKPOINT
$template
question: <one design-selecting question>
why design-changing: <affected scope field or normative guarantee>"
write_skill "$reloc_root" design "# Design

$template

More prose.

$template

Even more prose.

$template"
write_skill "$reloc_root" review-loop "# Review loop

$charter_label
$template

$template
focus: <review focus, unchanged>"
write_skill "$reloc_root" work-issue "# Work issue

$template"
assert_fails 'label relocated to the plain carrier' "$reloc_root" \
	'review-dispatch carrier lost its canonical CHARTER label'

# Dropping the focus line makes the dispatch carrier unidentifiable even with
# the label intact; the gate fails closed rather than guessing.
unmarked_root=$tmp_root/unmarked
cp -R "$pass_root" "$unmarked_root"
replace_first_line "$unmarked_root/content/skills/review-loop/SKILL.md" \
	'focus: <review focus, unchanged>' \
	'focus: <whatever the reviewer asks about>'
assert_fails 'unmarked dispatch carrier' "$unmarked_root" \
	'expected exactly one review-dispatch carrier'

# Editing a carrier's first line makes it invisible to the first-line scan;
# the site manifest must still catch it.
anchor_root=$tmp_root/anchor
cp -R "$pass_root" "$anchor_root"
replace_first_line "$anchor_root/content/skills/design/SKILL.md" \
	'interaction: <unchanged root value>' \
	'interaction: <inferred from nesting>'
assert_fails 'mutated first line' "$anchor_root" \
	'design/SKILL.md: expected 3 carrier(s), found 2'

# Deleting one complete carrier is the same failure through the manifest.
removed_root=$tmp_root/removed
mkdir -p "$removed_root"
cp -R "$pass_root/content" "$removed_root/content"
rm "$removed_root/content/skills/work-issue/SKILL.md"
write_skill "$removed_root" work-issue '# Work issue

The carrier was deleted here.'
assert_fails 'deleted carrier' "$removed_root" \
	'work-issue/SKILL.md: expected 1 carrier(s), found 0'

# A manifest site that vanishes with its skill is named, not scanned past.
missing_root=$tmp_root/missing
mkdir -p "$missing_root"
cp -R "$pass_root/content" "$missing_root/content"
rm -R "$missing_root/content/skills/work-issue"
assert_fails 'deleted site' "$missing_root" \
	'expected carrier site is missing: work-issue/SKILL.md'

# A root with no carriers at all must not report success.
empty_root=$tmp_root/empty
write_skill "$empty_root" brainstorming '# Brainstorming

No carrier here.'
assert_fails 'no carriers' "$empty_root" 'no carrier occurrences'

# A carrier added to a file outside the manifest is still window-checked.
extra_root=$tmp_root/extra
cp -R "$pass_root" "$extra_root"
write_skill "$extra_root" scope "# Scope

$template"
assert_passes 'carrier in a new file' "$extra_root"

# Fixtures under testdata/ are excluded, mirroring the installer's filter.
testdata_root=$tmp_root/testdata
cp -R "$pass_root" "$testdata_root"
mkdir -p "$testdata_root/content/skills/design/testdata"
printf 'interaction: <unchanged root value>\nnot a carrier\n' \
	>"$testdata_root/content/skills/design/testdata/fixture.md"
assert_passes 'testdata excluded' "$testdata_root"

printf 'carrier-drift-test: pass\n'
