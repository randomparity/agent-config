#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'workflow-scope-contract-test: %s\n' "$*" >&2
	exit 1
}

marker_line() {
	local file=$1 marker=$2 matches count
	if ! matches=$(rg -n --fixed-strings --line-regexp "$marker" "$file"); then
		fail "$file: missing marker: $marker"
	fi
	count=$(printf '%s\n' "$matches" | awk 'END { print NR }')
	[[ "$count" -eq 1 ]] || fail "$file: duplicate marker: $marker"
	printf '%s\n' "${matches%%:*}"
}

assert_ordered_clause() {
	local file=$1 first=$2 first_value=$3 second=$4 second_value=$5
	local first_line second_line actual
	first_line=$(marker_line "$file" "<!-- SCOPE-ORDER:$first -->")
	second_line=$(marker_line "$file" "<!-- SCOPE-ORDER:$second -->")
	actual=$(sed -n "$((first_line + 1))p" "$file")
	[[ "$actual" == "$first_value" ]] ||
		fail "$file: order marker $first does not own: $first_value"
	actual=$(sed -n "$((second_line + 1))p" "$file")
	[[ "$actual" == "$second_value" ]] ||
		fail "$file: order marker $second does not own: $second_value"
	[[ "$first_line" -lt "$second_line" ]] ||
		fail "$file: expected order marker $first before $second"
}

bounded_block() {
	local file=$1 kind=$2 name=$3 start end start_line end_line
	start="<!-- SCOPE-$kind:$name -->"
	end="<!-- SCOPE-$kind:END:$name -->"
	start_line=$(marker_line "$file" "$start")
	end_line=$(marker_line "$file" "$end")
	[[ "$start_line" -lt "$end_line" ]] ||
		fail "$file: reversed markers for $kind $name"
	sed -n "$((start_line + 1)),$((end_line - 1))p" "$file"
}

assert_carrier() {
	local file=$1 name=$2 block expected count
	block=$(bounded_block "$file" CARRIER "$name")
	[[ -n "$block" ]] || fail "$file: missing carrier block: $name"
	while IFS= read -r expected; do
		if ! count=$(printf '%s\n' "$block" | rg -c -x --fixed-strings -- "$expected"); then
			fail "$file: carrier $name missing value: $expected"
		fi
		[[ "$count" -eq 1 ]] || fail "$file: carrier $name duplicate value: $expected"
	done <<'EOF'
interaction: <unchanged root value>
scope identity: <external scope identity, never reviewed target>
outcome: <frozen external outcome>
completion criteria: <frozen external completion criteria>
provenance: <external source for every outcome, criterion, and user decision>
exclusions: <frozen external exclusions>
surface: <frozen permitted surface>
ambiguities: <frozen ambiguity list>
EOF
}

assert_rule() {
	local file=$1 name=$2 expected=$3 block count
	block=$(bounded_block "$file" RULE "$name")
	[[ -n "$block" ]] || fail "$file: missing rule block: $name"
	if ! count=$(printf '%s\n' "$block" | rg -c -x --fixed-strings -- "$expected"); then
		fail "$file: rule $name missing instruction: $expected"
	fi
	[[ "$count" -eq 1 ]] || fail "$file: rule $name duplicate instruction: $expected"
}

assert_block_contains() {
	local file=$1 kind=$2 name=$3 expected=$4 block count
	block=$(bounded_block "$file" "$kind" "$name")
	if ! count=$(printf '%s\n' "$block" | rg -c -x --fixed-strings -- "$expected"); then
		fail "$file: $kind $name missing value: $expected"
	fi
	[[ "$count" -eq 1 ]] || fail "$file: $kind $name duplicate value: $expected"
}

skill_path() {
	local root=$1 skill=$2
	printf '%s/%s/SKILL.md\n' "$root" "$skill"
}

check_contract() {
	local root=$1 work brainstorm design plans
	work=$(skill_path "$root" work-issue)
	brainstorm=$(skill_path "$root" brainstorming)
	design=$(skill_path "$root" design)
	plans=$(skill_path "$root" writing-plans)
	assert_ordered_clause "$work" work-frozen "## Frozen scope charter" \
		work-design "## 3. Design"
	assert_carrier "$work" work-issue-to-design
	assert_carrier "$design" design-to-brainstorming
	assert_carrier "$design" design-to-writing-plans
	assert_carrier "$brainstorm" brainstorming-checkpoint
	assert_block_contains "$brainstorm" CARRIER brainstorming-checkpoint \
		"question: <one design-selecting question>"
	assert_block_contains "$brainstorm" CARRIER brainstorming-checkpoint \
		"why design-changing: <affected scope field or normative guarantee>"
	assert_ordered_clause "$work" work-checkpoint "### SCOPE CHECKPOINT" \
		work-unattended "### Unattended parking"
	assert_ordered_clause "$design" design-user-decision \
		"An explicit user decision may authorize a guarantee only when provenance records it." \
		design-high-risk \
		"High-risk examples begin with transactions, persistence, concurrency, and recovery."
	assert_rule "$design" necessary-consequence \
		"No reasonable implementation can satisfy the sourced completion criterion without it."
	assert_rule "$design" direct-design-charter \
		"An interactive direct invocation freezes its quoted request into all eight fields."
	assert_rule "$design" direct-design-charter \
		"An unattended direct invocation without a complete charter parks before design."
	assert_rule "$plans" inherit-interaction \
		"Inherit interaction from the root; never infer it from nesting."
}

rewrite_block_line_once() {
	local file=$1 kind=$2 name=$3 old=$4 new=$5 start end block count tmp
	start="<!-- SCOPE-$kind:$name -->"
	end="<!-- SCOPE-$kind:END:$name -->"
	block=$(bounded_block "$file" "$kind" "$name")
	if ! count=$(printf '%s\n' "$block" | rg -c -x --fixed-strings -- "$old"); then
		fail "$file: $kind $name missing mutation literal: $old"
	fi
	[[ "$count" -eq 1 ]] || fail "$file: duplicate mutation literal: $old"
	tmp=$file.scope-tmp
	if ! awk -v start="$start" -v end="$end" -v old="$old" -v new="$new" '
    $0 == start { active = 1 }
    active && $0 == old { print new; changed++; next }
    $0 == end { active = 0 }
    { print }
    END { if (changed != 1) exit 42 }
  ' "$file" >"$tmp"; then
		fail "$file: failed bounded rewrite: $old"
	fi
	mv "$tmp" "$file"
}

rewrite_exact_line_once() {
	local file=$1 old=$2 new=$3 matches count tmp
	if ! matches=$(rg -n -x --fixed-strings -- "$old" "$file"); then
		fail "$file: missing mutation line: $old"
	fi
	count=$(printf '%s\n' "$matches" | awk 'END { print NR }')
	[[ "$count" -eq 1 ]] || fail "$file: duplicate mutation line: $old"
	tmp=$file.scope-tmp
	awk -v old="$old" -v new="$new" '$0 == old { print new; next } { print }' \
		"$file" >"$tmp"
	mv "$tmp" "$file"
}

duplicate_exact_line_once() {
	local file=$1 line=$2 matches count tmp
	if ! matches=$(rg -n -x --fixed-strings -- "$line" "$file"); then
		fail "$file: missing duplication line: $line"
	fi
	count=$(printf '%s\n' "$matches" | awk 'END { print NR }')
	[[ "$count" -eq 1 ]] || fail "$file: duplicate duplication line: $line"
	tmp=$file.scope-tmp
	awk -v line="$line" '$0 == line { print; print; next } { print }' "$file" >"$tmp"
	mv "$tmp" "$file"
}

move_ordered_clause_after() {
	local file=$1 moving=$2 moving_value=$3 anchor=$4 anchor_value=$5 tmp
	local moving_marker="<!-- SCOPE-ORDER:$moving -->"
	local anchor_marker="<!-- SCOPE-ORDER:$anchor -->"
	assert_ordered_clause "$file" "$moving" "$moving_value" "$anchor" "$anchor_value"
	tmp=$file.scope-tmp
	if ! awk -v moving="$moving_marker" -v anchor="$anchor_marker" '
    $0 == moving { saved_marker = $0; getline saved_value; next }
    $0 == anchor {
      print
      getline
      print
      print saved_marker
      print saved_value
      moved = 1
      next
    }
    { print }
    END { if (moved != 1) exit 42 }
  ' "$file" >"$tmp"; then
		fail "$file: failed to move order marker $moving after $anchor"
	fi
	mv "$tmp" "$file"
}

copy_fixture() {
	local case_name=$1 fixture skill
	fixture=$scratch/$case_name
	mkdir -p "$fixture"
	for skill in work-issue brainstorming design writing-plans review-loop challenge; do
		cp -R "$canonical_root/$skill" "$fixture/$skill"
	done
	printf '%s\n' "$fixture"
}

assert_case_fails() {
	local case_name=$1 expected=$2 fixture_root=$3 output
	if output=$(check_contract "$fixture_root" 2>&1); then
		fail "$case_name: mutation unexpectedly passed"
	fi
	printf '%s\n' "$output" | rg -q --fixed-strings -- "$expected" ||
		fail "$case_name: wrong failure; expected '$expected', got '$output'"
}

assert_fixture_fails() {
	assert_case_fails "$@"
	fixture_count=$((fixture_count + 1))
}

assert_extractor_fails() {
	assert_case_fails "$@"
	extractor_count=$((extractor_count + 1))
}

run_scope_fixtures() {
	local fixture file
	fixture=$(copy_fixture scope-02)
	file=$(skill_path "$fixture" design)
	move_ordered_clause_after "$file" design-user-decision \
		"An explicit user decision may authorize a guarantee only when provenance records it." \
		design-high-risk \
		"High-risk examples begin with transactions, persistence, concurrency, and recovery."
	assert_fixture_fails scope-02 \
		"expected order marker design-user-decision before design-high-risk" "$fixture"

	fixture=$(copy_fixture scope-03)
	file=$(skill_path "$fixture" design)
	rewrite_block_line_once "$file" CARRIER design-to-brainstorming \
		"interaction: <unchanged root value>" \
		"interaction: <unattended because this call is nested>"
	assert_fixture_fails scope-03 \
		"carrier design-to-brainstorming missing value: interaction: <unchanged root value>" \
		"$fixture"

	fixture=$(copy_fixture scope-05)
	file=$(skill_path "$fixture" work-issue)
	move_ordered_clause_after "$file" work-checkpoint "### SCOPE CHECKPOINT" \
		work-unattended "### Unattended parking"
	assert_fixture_fails scope-05 \
		"expected order marker work-checkpoint before work-unattended" "$fixture"
}

run_extractor_tests() {
	local fixture file
	fixture=$(copy_fixture extractor-missing-end)
	file=$(skill_path "$fixture" design)
	rewrite_exact_line_once "$file" \
		"<!-- SCOPE-CARRIER:END:design-to-brainstorming -->" \
		"<!-- removed end marker; later carrier prose remains -->"
	assert_extractor_fails extractor-missing-end \
		"missing marker: <!-- SCOPE-CARRIER:END:design-to-brainstorming -->" "$fixture"

	fixture=$(copy_fixture extractor-duplicate-end)
	file=$(skill_path "$fixture" design)
	duplicate_exact_line_once "$file" \
		"<!-- SCOPE-CARRIER:END:design-to-brainstorming -->"
	assert_extractor_fails extractor-duplicate-end \
		"duplicate marker: <!-- SCOPE-CARRIER:END:design-to-brainstorming -->" "$fixture"

	fixture=$(copy_fixture extractor-reversed-end)
	file=$(skill_path "$fixture" design)
	rewrite_exact_line_once "$file" \
		"<!-- SCOPE-CARRIER:design-to-brainstorming -->" \
		"<!-- SCOPE-CARRIER:TEMP:design-to-brainstorming -->"
	rewrite_exact_line_once "$file" \
		"<!-- SCOPE-CARRIER:END:design-to-brainstorming -->" \
		"<!-- SCOPE-CARRIER:design-to-brainstorming -->"
	rewrite_exact_line_once "$file" \
		"<!-- SCOPE-CARRIER:TEMP:design-to-brainstorming -->" \
		"<!-- SCOPE-CARRIER:END:design-to-brainstorming -->"
	assert_extractor_fails extractor-reversed-end \
		"reversed markers for CARRIER design-to-brainstorming" "$fixture"
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
canonical_root=$repo_root/content/skills
scratch_prefix=${TMPDIR:-/tmp}/workflow-scope-contract-test
scratch=$(mktemp -d "$scratch_prefix.XXXXXX")
case "$scratch" in
"$scratch_prefix".*) ;;
*) fail "unsafe scratch path: $scratch" ;;
esac

cleanup() {
	[[ -d "$scratch" && "$scratch" == "$scratch_prefix".* ]] || return 0
	rm -R -- "$scratch"
}
trap cleanup EXIT

fixture_count=0
extractor_count=0
check_contract "$canonical_root"
run_scope_fixtures
run_extractor_tests
[[ "$fixture_count" -eq 3 ]] || fail "expected 3 SCOPE fixtures, got $fixture_count"
[[ "$extractor_count" -eq 3 ]] || fail "expected 3 extractor tests, got $extractor_count"
printf 'workflow-scope-contract-test: ok (%d fixtures, %d extractor tests)\n' \
	"$fixture_count" "$extractor_count"
