#!/usr/bin/env bash
set -euo pipefail

# Fixture suites for scripts/check-carrier-drift.sh: each fixture is a
# content root holding only content/skills/<name>/SKILL.md files, which is
# all the gate reads.

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

# A passing root: one plain carrier, one CHARTER-labelled review-dispatch
# carrier with a trailing focus line, and one checkpoint carrier with two
# trailing lines — surrounding lines must not disturb the window match.
pass_root=$tmp_root/pass
write_skill "$pass_root" one "# One

$template

Free prose."
write_skill "$pass_root" two "# Two

$charter_label
$template
focus: <review focus, unchanged>"
write_skill "$pass_root" three "# Three

SCOPE CHECKPOINT
$template
question: <one design-selecting question>
why design-changing: <affected scope field or normative guarantee>"

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

assert_passes 'canonical carriers' "$pass_root"

# A drifted field line inside one carrier of many.
drift_root=$tmp_root/drift
cp -R "$pass_root" "$drift_root"
sed -i 's|surface: <frozen permitted surface>|surface: <whatever the reviewer allows>|' \
	"$drift_root/content/skills/two/SKILL.md"
assert_fails 'drifted window' "$drift_root" 'carrier drifted from the canonical template'

# The CHARTER label is the parsing boundary challenge consumes; a one-sided
# rename must fail even when the eight lines below it are intact.
label_root=$tmp_root/label
cp -R "$pass_root" "$label_root"
sed -i 's|^CHARTER (scope authority.*|CHARTER (reviewer may restate the fields below):|' \
	"$label_root/content/skills/two/SKILL.md"
assert_fails 'drifted CHARTER label' "$label_root" 'CHARTER label drifted'

# A root with no carriers at all must not report success.
empty_root=$tmp_root/empty
write_skill "$empty_root" one '# One

No carrier here.'
assert_fails 'no carriers' "$empty_root" 'no carrier occurrences'

# A single carrier makes drift unobservable.
single_root=$tmp_root/single
write_skill "$single_root" one "# One

$template"
assert_fails 'single carrier' "$single_root" 'drift is unobservable below two'

# Fixtures under testdata/ are excluded, mirroring the installer's filter.
testdata_root=$tmp_root/testdata
write_skill "$testdata_root" one "# One

$template"
mkdir -p "$testdata_root/content/skills/one/testdata"
printf 'interaction: <unchanged root value>\nnot a carrier\n' \
	>"$testdata_root/content/skills/one/testdata/fixture.md"
write_skill "$testdata_root" two "# Two

$charter_label
$template"
assert_passes 'testdata excluded' "$testdata_root"

printf 'carrier-drift-test: pass\n'
