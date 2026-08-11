#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'install-test: %s\n' "$*" >&2
	exit 1
}

assert_file() {
	[[ -f "$1" ]] || fail "expected file: $1"
}

assert_same_file() {
	local expected="$1"
	local actual="$2"

	cmp -s "$expected" "$actual" ||
		fail "expected identical files: $expected and $actual"
}

assert_not_file() {
	[[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
	local file="$1"
	local expected="$2"
	grep -Fq "$expected" "$file" || fail "expected $file to contain: $expected"
}

assert_worktree_baseline_transcripts() {
	local skill_file="$1"

	# WT-BL-00: a passing baseline remains ready to implement.
	assert_contains "$skill_file" '**If tests pass:** Report ready.'
	# WT-BL-01: interactive failure preserves the human decision gate.
	assert_contains "$skill_file" '**Interactive mode:**'
	assert_contains "$skill_file" \
		'Report the failures, ask whether to proceed or investigate, and wait.'
	# WT-BL-02: unresolved dispatched failure returns control as a blocker.
	assert_contains "$skill_file" '**Dispatched mode without resolving authority:**'
	assert_contains "$skill_file" \
		'Report the failures as a blocker and return to the caller.'
	# WT-BL-03: only authority that addresses the failed baseline resolves the gate.
	assert_contains "$skill_file" '**Dispatched mode with resolving authority:**'
	assert_contains "$skill_file" \
		'An applicable caller instruction or repository rule must explicitly address the failed baseline.'
	assert_contains "$skill_file" \
		'Report the failures, then follow the explicit applicable instruction or repository rule.'
	# WT-BL-04: generic dispatch does not imply permission to continue.
	assert_contains "$skill_file" \
		'Generic dispatch, autonomy, or task-completion language does not resolve the gate.'
	# WT-BL-05: unresolved ambiguity or conflict follows the blocker branch.
	assert_contains "$skill_file" \
		'If instruction priority does not yield one unambiguous action, return the blocker.'
}

assert_line() {
	local file="$1"
	local expected="$2"

	grep -Fxq -- "$expected" "$file" ||
		fail "expected $file to contain line: $expected"
}

assert_json_value() {
	local file="$1"
	local filter="$2"
	local expected="$3"
	local actual

	actual="$(jq -r "$filter" "$file")"
	[[ "$actual" == "$expected" ]] ||
		fail "expected $file $filter to be $expected, got $actual"
}

assert_toml_contains() {
	assert_contains "$1" "$2"
}

assert_executable() {
	[[ -x "$1" ]] || fail "expected executable: $1"
}

# The canonical tree carries test-only assets under `testdata` entries that the
# installer filters out, so the installed tree is the canonical one minus those.
# Compare with the same exclusion rather than loosening the comparison. `diff -x`
# and the `find` below both match by name and not by type, which is the rule
# `stage_skills` applies (ADR 0025).
assert_canonical_skills() {
	local destination="$1"
	local expected_executables
	local actual_executables
	local count

	diff -rq -x testdata "$REPO/content/skills" "$destination/skills" >/dev/null ||
		fail "installed skills differ from canonical tree: $destination/skills"
	expected_executables="$(
		cd "$REPO/content/skills" || exit
		find . -name testdata -prune -o -type f \
			\( -perm -100 -o -perm -010 -o -perm -001 \) -print |
			LC_ALL=C sort
	)"
	actual_executables="$(
		cd "$destination/skills" || exit
		find . -type f \( -perm -100 -o -perm -010 -o -perm -001 \) -print |
			LC_ALL=C sort
	)"
	[[ "$actual_executables" == "$expected_executables" ]] ||
		fail "installed skill modes differ from canonical tree: $destination/skills"
	count="$(find "$destination/skills" ! -path "$destination/skills" \
		-prune -type d -print | wc -l)"
	[[ "$count" -eq 36 ]] ||
		fail "expected 36 canonical skills in $destination/skills, got $count"
	assert_file "$destination/skills/simplify-changes/SKILL.md"
	assert_not_file "$destination/skills/simplify/SKILL.md"
}

# The tracker contract suite's stub profile answers a read with a fabricated
# issue. Installed, it is selectable as though it were a tracker and nothing at
# the call site distinguishes its payload from a real one, so assert both that
# it is absent and that naming it fails the way any unimplemented tracker does.
assert_no_stub_profile() {
	local destination="$1"
	local assets="$destination/skills/github-tracking/assets"
	local leftover
	local installed_profiles
	local status=0
	local available

	assert_file "$assets/tracker.sh"
	# The whole set, not just the stub's name: a second fixture under any other
	# name would otherwise ship with no gate failing. Adding a real tracker
	# profile is a deliberate edit here, which is the property this has and a
	# check for one absent filename does not.
	installed_profiles="$(
		cd "$assets/profiles" || exit
		find . -type f -print | LC_ALL=C sort
	)"
	[[ "$installed_profiles" == './github.sh' ]] ||
		fail "unexpected installed profiles: $installed_profiles"
	leftover="$(find "$destination/skills" -name testdata -print)"
	[[ -z "$leftover" ]] ||
		fail "installed tree carries a test-only asset entry: $leftover"

	"$assets/tracker.sh" view --profile fixture 1 \
		>"$tmpdir/tracker-out" 2>"$tmpdir/tracker-err" || status="$?"
	[[ "$status" -eq 1 ]] ||
		fail "installed tracker did not reject --profile fixture (exit $status)"
	assert_json_value "$tmpdir/tracker-err" ".error" "usage"
	available="$(jq -r '.message | sub("^.*available: "; "")' "$tmpdir/tracker-err")"
	[[ "$available" != *fixture* ]] ||
		fail "installed tracker still advertises the stub profile: $available"
}

# ADR 0025: no test suite reaches an installed tree, with one recorded exception.
# `decision-records/assets/check-records-test.sh` is delivered content — the skill
# instructs an agent to copy six files out of the installed `assets/` directory
# into an adopting repo, and that suite is one of them — so its *presence* is
# asserted too. Dropping it would break the skill's documented adoption at the
# point of use, where no gate here can see it; failing this assertion is what
# sends an author who deletes it back to the record.
assert_no_test_suites() {
	local destination="$1"
	local skills="$destination/skills"
	local shipped

	assert_not_file "$skills/brainstorming/scripts/start-server-test.sh"
	assert_not_file "$skills/issue/scripts/create-verified-issue-test.sh"
	assert_file "$skills/decision-records/assets/check-records-test.sh"

	# The whole set rather than the three names above, so a second suite under
	# any other name fails here too. It enforces the repository's `*-test.sh`
	# convention, not "is this file a test": a suite named `foo_test.sh` or
	# written in another language is not caught here. Name a new suite
	# `*-test.sh` and put it in `testdata/` — that convention is what this
	# assertion can see.
	shipped="$(
		cd "$skills" || exit
		find . -type f -name '*-test.sh' -print | LC_ALL=C sort
	)"
	[[ "$shipped" == './decision-records/assets/check-records-test.sh' ]] ||
		fail "installed tree carries test suites: $shipped"
}

assert_tree_contains() {
	local dir="$1"
	local expected="$2"

	rg -q --fixed-strings "$expected" "$dir" ||
		fail "expected $dir to contain: $expected"
}

write_json() {
	local path="$1"
	local body="$2"

	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$body" >"$path"
}

write_text() {
	local path="$1"
	local body="$2"

	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$body" >"$path"
}

seed_stale_manifest() {
	local dest="$1"

	mkdir -p "$dest"
	write_text "$dest/stale-managed.txt" "stale"
	write_text "$dest/runtime-state.txt" "runtime"
	write_text "$dest/.agent-config-manifest" "stale-managed.txt"
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-test.XXXXXX")"
trap 'rm -R "$tmpdir"' EXIT

assert_worktree_baseline_transcripts \
	"$REPO/content/skills/using-git-worktrees/SKILL.md"

export HOME="$tmpdir/home"
export CLAUDE_CONFIG_DIR="$tmpdir/home/.claude"
export CODEX_CONFIG_DIR="$tmpdir/home/.codex"
export BOB_CONFIG_DIR="$tmpdir/home/.bob"
export AGENT_CONFIG_PRIVATE_DIR="$tmpdir/private"
export AGENT_CONFIG_REGISTER_CLAUDE_MCP=0

mkdir -p "$HOME"
seed_stale_manifest "$CLAUDE_CONFIG_DIR"
seed_stale_manifest "$CODEX_CONFIG_DIR"
seed_stale_manifest "$BOB_CONFIG_DIR"

write_json \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/claude/settings.overlay.json" \
	'{"env":{"AGENT_CONFIG_TEST":"claude"}}'
write_text \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/codex/config.overlay.toml" \
	'agent_config_test = "codex"'
write_json \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/bob/settings.overlay.json" \
	'{"agentConfigTest":{"bob":true}}'
write_json \
	"$AGENT_CONFIG_PRIVATE_DIR/hosts/test-host/bob/mcp.overlay.json" \
	'{
  "mcpServers": {
    "example-docs": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-fetch"]
    }
  }
}'

AGENT_CONFIG_HOST=test-host ./install.sh --agent all

assert_file "$CLAUDE_CONFIG_DIR/CLAUDE.md"
assert_file "$CLAUDE_CONFIG_DIR/settings.json"
assert_canonical_skills "$CLAUDE_CONFIG_DIR"
assert_executable \
	"$CLAUDE_CONFIG_DIR/skills/preflight/scripts/detect-host-architecture"
assert_executable \
	"$CLAUDE_CONFIG_DIR/skills/preflight/scripts/resolve-architecture-context"
assert_no_stub_profile "$CLAUDE_CONFIG_DIR"
assert_no_test_suites "$CLAUDE_CONFIG_DIR"
assert_not_file "$CLAUDE_CONFIG_DIR/skills/accessibility-reviewer/SKILL.md"
assert_not_file "$CLAUDE_CONFIG_DIR/skills/project-context/SKILL.md"
assert_worktree_baseline_transcripts \
	"$CLAUDE_CONFIG_DIR/skills/using-git-worktrees/SKILL.md"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$CLAUDE_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_file "$CLAUDE_CONFIG_DIR/languages/bash.md"
assert_executable "$CLAUDE_CONFIG_DIR/statusline.sh"
assert_json_value "$CLAUDE_CONFIG_DIR/settings.json" ".env.AGENT_CONFIG_TEST" "claude"

assert_file "$CODEX_CONFIG_DIR/AGENTS.md"
assert_file "$CODEX_CONFIG_DIR/config.toml"
assert_canonical_skills "$CODEX_CONFIG_DIR"
assert_executable \
	"$CODEX_CONFIG_DIR/skills/preflight/scripts/detect-host-architecture"
assert_executable \
	"$CODEX_CONFIG_DIR/skills/preflight/scripts/resolve-architecture-context"
assert_no_stub_profile "$CODEX_CONFIG_DIR"
assert_no_test_suites "$CODEX_CONFIG_DIR"
assert_not_file "$CODEX_CONFIG_DIR/skills/accessibility-reviewer/SKILL.md"
assert_not_file "$CODEX_CONFIG_DIR/skills/project-context/SKILL.md"
assert_worktree_baseline_transcripts \
	"$CODEX_CONFIG_DIR/skills/using-git-worktrees/SKILL.md"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$CODEX_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_file "$CODEX_CONFIG_DIR/references/orchestration.md"
assert_toml_contains "$CODEX_CONFIG_DIR/config.toml" 'agent_config_test = "codex"'

assert_file "$BOB_CONFIG_DIR/settings.json"
assert_file "$BOB_CONFIG_DIR/settings/custom_modes.yaml"
assert_file "$BOB_CONFIG_DIR/custom_modes.yaml"
assert_file "$BOB_CONFIG_DIR/mcp.json"
assert_file "$BOB_CONFIG_DIR/mcp_settings.json"
assert_file "$BOB_CONFIG_DIR/rules/global-development-standards.md"
assert_canonical_skills "$BOB_CONFIG_DIR"
assert_executable \
	"$BOB_CONFIG_DIR/skills/preflight/scripts/detect-host-architecture"
assert_executable \
	"$BOB_CONFIG_DIR/skills/preflight/scripts/resolve-architecture-context"
assert_no_stub_profile "$BOB_CONFIG_DIR"
assert_no_test_suites "$BOB_CONFIG_DIR"
assert_not_file "$BOB_CONFIG_DIR/skills/accessibility-reviewer/SKILL.md"
assert_not_file "$BOB_CONFIG_DIR/skills/project-context/SKILL.md"
assert_worktree_baseline_transcripts \
	"$BOB_CONFIG_DIR/skills/using-git-worktrees/SKILL.md"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$BOB_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_json_value "$BOB_CONFIG_DIR/settings.json" ".agentConfigTest.bob" "true"
assert_json_value "$BOB_CONFIG_DIR/mcp.json" '.mcpServers["example-docs"].command' "npx"
assert_json_value "$BOB_CONFIG_DIR/mcp_settings.json" '.mcpServers["example-docs"].command' "npx"

assert_line "$CLAUDE_CONFIG_DIR/.agent-config-manifest" \
	"licenses/superpowers.LICENSE"
assert_line "$CODEX_CONFIG_DIR/.agent-config-manifest" \
	"licenses/superpowers.LICENSE"
assert_line "$BOB_CONFIG_DIR/.agent-config-manifest" \
	"licenses/superpowers.LICENSE"

assert_not_file "$CLAUDE_CONFIG_DIR/stale-managed.txt"
assert_not_file "$CODEX_CONFIG_DIR/stale-managed.txt"
assert_not_file "$BOB_CONFIG_DIR/stale-managed.txt"
assert_file "$CLAUDE_CONFIG_DIR/runtime-state.txt"
assert_file "$CODEX_CONFIG_DIR/runtime-state.txt"
assert_file "$BOB_CONFIG_DIR/runtime-state.txt"

mode_drift="$CODEX_CONFIG_DIR/skills/brainstorming/scripts/start-server.sh"
chmod 644 "$mode_drift"
[[ ! -x "$mode_drift" ]] || fail "expected executable drift fixture: $mode_drift"
AGENT_CONFIG_HOST=test-host ./install.sh --agent codex
assert_executable "$mode_drift"
assert_canonical_skills "$CODEX_CONFIG_DIR"

write_text "$CLAUDE_CONFIG_DIR/CLAUDE.md" "local drift before reinstall"
write_text "$CLAUDE_CONFIG_DIR/licenses/superpowers.LICENSE" \
	"local license drift before reinstall"
AGENT_CONFIG_HOST=test-host ./install.sh --agent claude

assert_contains "$CLAUDE_CONFIG_DIR/CLAUDE.md" "# Global Development Standards"
assert_tree_contains "$CLAUDE_CONFIG_DIR/.agent-config-backups" "local drift before reinstall"
assert_same_file \
	"docs/licenses/superpowers.LICENSE" \
	"$CLAUDE_CONFIG_DIR/licenses/superpowers.LICENSE"
assert_tree_contains "$CLAUDE_CONFIG_DIR/.agent-config-backups" \
	"local license drift before reinstall"

# Upgrading an install that predates ADR 0025: its destination still holds the
# suites this change stopped shipping. Nothing prunes them by name — the manifest
# entry is `skills`, so what removes them is `install_managed_path` seeing the
# payload differ and replacing the whole tree. Seed one and re-assert, or the
# guarantee would hold only for a fresh install.
stale_suite="$CLAUDE_CONFIG_DIR/skills/issue/scripts/create-verified-issue-test.sh"
write_text "$stale_suite" '#!/usr/bin/env bash'
AGENT_CONFIG_HOST=test-host ./install.sh --agent claude
assert_not_file "$stale_suite"
assert_no_test_suites "$CLAUDE_CONFIG_DIR"
assert_canonical_skills "$CLAUDE_CONFIG_DIR"

# ADR 0025's exclusion matches an entry *named* `testdata`, file or directory.
# Nothing above reaches the file half of that rule: every case so far installs
# from the real repository, which carries no plain file by that name, so
# narrowing `stage_skills` back to `-type d` leaves them all green. Install from
# a copy of the repository with such a file planted in it instead.
#
# The copy takes the four repository paths `install.sh` reads under rather than
# the whole tree, so a read that leaves them fails loudly here, naming the
# fixture path, instead of being satisfied by whatever a blanket copy happened
# to carry. Both the copy and its destination sit under `$tmpdir`, so the
# suite's existing trap removes them.
fixture_repo="$tmpdir/fixture-repo"
fixture_dest="$tmpdir/fixture-dest"
# Both names are written once and read everywhere below. Spelling either at each
# use lets an edit reach the planted entry and not the assertion that looks for
# it, which leaves this case green while testing nothing — the vacuous-assertion
# failure ADR 0025 names.
fixture_skill=fixture-only
fixture_entry=testdata
# The skill has to be one the canonical tree does not carry, for the reason the
# install call below gives. That is a property of the name, so assert it rather
# than trusting the reader of a comment to preserve it.
[[ ! -e "$REPO/content/skills/$fixture_skill" ]] ||
	fail "fixture skill must be absent from the canonical tree: $fixture_skill"
mkdir -p "$fixture_repo/docs"
cp -pR "$REPO/install.sh" "$REPO/content" "$REPO/agents" "$fixture_repo/"
cp -pR "$REPO/docs/licenses" "$fixture_repo/docs/"
fixture_plant="$fixture_repo/content/skills/$fixture_skill/$fixture_entry"
write_text "$fixture_repo/content/skills/$fixture_skill/SKILL.md" '# fixture only'
write_text "$fixture_plant" 'not a directory'
# The file half of the rule is the whole point of this case. A plant that became
# a directory would re-test the coverage every case above already has, and the
# `find` below matches either type by design, so nothing else would notice.
[[ -f "$fixture_plant" ]] ||
	fail "fixture plant must be a plain file: $fixture_plant"

# A one-shot destination rather than the exported one, so the assertions above
# keep the tree they were made against.
#
# The copy's installer, not `./install.sh`. Every case above runs the latter and
# the fixture's copy is byte-identical, so normalising this call to match them
# looks like a no-op — `install.sh` takes its repository root from
# `${BASH_SOURCE[0]}`, and the fixture would stop being staged at all. What
# catches that is the skill above existing only in the copy: the assertions then
# cannot be satisfied by an install that read the real repository.
CLAUDE_CONFIG_DIR="$fixture_dest" AGENT_CONFIG_HOST=test-host \
	"$fixture_repo/install.sh" --agent claude

# The fixture-only skill first: it carries both that the install staged
# something and that what it staged was the copy.
assert_file "$fixture_dest/skills/$fixture_skill/SKILL.md"
# The whole set rather than the planted path, matching `assert_no_stub_profile`.
# It matches either type, so it re-asserts the directory half of the rule
# against the copy rather than only the file the plant added.
fixture_leftover="$(find "$fixture_dest/skills" -name "$fixture_entry" -print)"
[[ -z "$fixture_leftover" ]] ||
	fail "fixture install carries a test-only asset entry: $fixture_leftover"

# --- Private overlays may not erase what the base defines (ADR 0043) ------------
#
# Every case below installs with a private overlay directory and a destination of its
# own rather than the exported ones. Four of them need mutually exclusive contents at
# the same overlay path, and the assertions above depend on the original overlay
# staying where it is, so sharing one directory would make each case's fixture the
# previous case's corruption.
#
# Both streams are captured because `install.sh` splits them: it refuses on standard
# error and reports progress — `applied private overlay`, `no private overlay at` — on
# standard output. A case asserts against whichever stream carries the message it is
# about, and asserting the message rather than only the exit status is what keeps an
# unrelated failure (an absent `jq`, a syntax error) from satisfying a refusal case.

OVERLAY_CASE=0

start_overlay_case() { # agent
	OVERLAY_CASE=$((OVERLAY_CASE + 1))
	OVERLAY_ROOT="$tmpdir/overlay-case-$OVERLAY_CASE"
	OVERLAY_PRIVATE="$OVERLAY_ROOT/private"
	OVERLAY_DEST="$OVERLAY_ROOT/dest"
	OVERLAY_OUT="$OVERLAY_ROOT/stdout"
	OVERLAY_ERR="$OVERLAY_ROOT/stderr"
	OVERLAY_FILE="$OVERLAY_PRIVATE/hosts/test-host/$1"
	mkdir -p "$OVERLAY_FILE" "$OVERLAY_DEST"
}

run_overlay_case() { # agent [repo-install-script]
	OVERLAY_STATUS=0
	AGENT_CONFIG_HOST=test-host \
		AGENT_CONFIG_PRIVATE_DIR="$OVERLAY_PRIVATE" \
		CLAUDE_CONFIG_DIR="$OVERLAY_DEST/claude" \
		CODEX_CONFIG_DIR="$OVERLAY_DEST/codex" \
		BOB_CONFIG_DIR="$OVERLAY_DEST/bob" \
		"${2:-./install.sh}" --agent "$1" \
		>"$OVERLAY_OUT" 2>"$OVERLAY_ERR" || OVERLAY_STATUS=$?
}

assert_overlay_refused() { # label
	[[ "$OVERLAY_STATUS" -ne 0 ]] ||
		fail "$1: install must refuse the overlay, got exit 0"
}

assert_overlay_installed() { # label
	[[ "$OVERLAY_STATUS" -eq 0 ]] ||
		fail "$1: install must succeed, got exit $OVERLAY_STATUS: $(cat "$OVERLAY_ERR")"
}

assert_stream_contains() { # stream-file needle label
	grep -Fq -- "$2" "$1" ||
		fail "$3: expected [$2] in $(basename "$1"): $(cat "$1")"
}

assert_stream_lacks() { # stream-file needle label
	! grep -Fq -- "$2" "$1" ||
		fail "$3: [$2] must not appear in $(basename "$1"): $(cat "$1")"
}

# Sorted so a key-order difference is not read as a value difference.
assert_json_equal() { # file-a file-b filter label
	local left right
	left="$(jq -S "$3" "$1")"
	right="$(jq -S "$3" "$2")"
	[[ "$left" == "$right" ]] ||
		fail "$4: $3 differs between $1 and $2"
}

BASE_SETTINGS="$REPO/agents/claude/shared/settings.base.json"

# 1. The settings Claude Code actually loads still carry every hook and deny entry the
#    base defines, read off the deployed file rather than the base the suite installed
#    from. Green before this change as well as after: it pins the property, and case 2
#    is what proves the property is enforced.
assert_json_equal "$CLAUDE_CONFIG_DIR/settings.json" "$BASE_SETTINGS" '.hooks' \
	'deployed hooks'
assert_json_equal "$CLAUDE_CONFIG_DIR/settings.json" "$BASE_SETTINGS" \
	'.permissions.deny' 'deployed permissions.deny'

# 2. The reported defect. Before ADR 0043 the install succeeds and deploys a
#    settings.json carrying one hook instead of the base's five.
#
#    The destination is empty here, so ADR 0049's empty-destination rule fills it from
#    the base rather than leaving it bare: what must not survive is the *merged* result,
#    not the file. Asserting the base's five hooks and the absence of the overlay's own
#    hook is the assertion that distinguishes the two — `assert_not_file` did so before
#    0049 and would now pass against an implementation that deployed nothing at all,
#    which is the state 0049 rule 4 exists to prevent.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" \
	'{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}]}}'
run_overlay_case claude
assert_overlay_refused 'clobbering hooks overlay'
assert_stream_contains "$OVERLAY_ERR" "$OVERLAY_FILE/settings.overlay.json" \
	'clobbering hooks overlay'
assert_stream_contains "$OVERLAY_ERR" 'hooks.PreToolUse' 'clobbering hooks overlay'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.hooks' \
	'clobbering hooks overlay'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.' \
	'clobbering hooks overlay'

# 3. The same loss reached through an object rather than an array: `*` replaces the
#    whole subtree, so the base's four privacy defaults leave without being named.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":null}'
run_overlay_case claude
assert_overlay_refused 'null env overlay'
assert_stream_contains "$OVERLAY_ERR" 'env' 'null env overlay'

# 4. The ancestor route. An unguarded lookup raises `Cannot index string with string
#    "PreToolUse"` here, so asserting the absence of that path is simultaneously the
#    outermost-paths-only rule and proof the message is not jq's traversal error.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"hooks":"x"}'
run_overlay_case claude
assert_overlay_refused 'non-indexable ancestor overlay'
assert_stream_contains "$OVERLAY_ERR" 'hooks' 'non-indexable ancestor overlay'
assert_stream_lacks "$OVERLAY_ERR" 'PreToolUse' 'non-indexable ancestor overlay'

# 5. The overlay this repository publishes for operators to copy. It is the one piece
#    of the out-of-repo compatibility surface that is in-repo, so it is the only part a
#    gate here can hold: this fires the day a base change breaks the documented example.
start_overlay_case claude
cp "$REPO/examples/hosts/example-host/claude/settings.overlay.json" \
	"$OVERLAY_FILE/settings.overlay.json"
run_overlay_case claude
assert_overlay_installed 'published example overlay'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.hooks' \
	'published example overlay'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" \
	'.permissions.deny' 'published example overlay'
assert_json_value "$OVERLAY_DEST/claude/settings.json" \
	'.permissions.allow[0]' 'Read(/path/to/project/**)'

# 8. The default configuration: no private overlay at all. Nothing else in the suite
#    reaches it — every case above writes an overlay first — so a check placed above
#    the overlay-present branch would abort every first-time install with the rest of
#    this file still green.
start_overlay_case claude
run_overlay_case claude
assert_overlay_installed 'absent overlay'
assert_stream_contains "$OVERLAY_OUT" 'no private overlay at' 'absent overlay'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.' \
	'absent overlay'

# 9. The rule is over the merged result, not over which paths the overlay names. An
#    overlay reproducing the base's array verbatim changes nothing, so it installs.
#    This is the only case that fails against a build which refuses on overlay shape.
start_overlay_case claude
jq '{permissions: {deny: .permissions.deny}}' "$BASE_SETTINGS" \
	>"$OVERLAY_FILE/settings.overlay.json"
run_overlay_case claude
assert_overlay_installed 'verbatim deny overlay'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" \
	'.permissions.deny' 'verbatim deny overlay'

# 10. The abort message promises the deployed file is untouched, and every case above
#     refuses into a tree where nothing was ever installed. Install once, then refuse
#     against that same destination, and read the file that is really on disk.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'pre-existing deployment'
write_json "$OVERLAY_FILE/settings.overlay.json" \
	'{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}]}}'
run_overlay_case claude
assert_overlay_refused 'refusal over a deployment'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.hooks' \
	'refusal over a deployment'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" \
	'.permissions.deny' 'refusal over a deployment'
assert_json_value "$OVERLAY_DEST/claude/settings.json" '.env.AGENT_CONFIG_TEST' first
# The run now continues past the refusal and reaches `prune_removed`, which the abort
# used to stop before. The manifest entry is the only thing standing between a withheld
# path and deletion, so assert the entry and not just the file (ADR 0049).
assert_line "$OVERLAY_DEST/claude/.agent-config-manifest" 'settings.json'
assert_stream_contains "$OVERLAY_ERR" 'has every array and object' 'refusal over a deployment'
assert_stream_lacks "$OVERLAY_ERR" 'is missing protected values' 'refusal over a deployment'

# 7. The empty-container exemption's one in-repo instance: `agents/bob/shared/mcp.json`
#    ships `{"mcpServers": {}}`, and replacing an empty container erases nothing, so
#    this installs. Fails against a build that protects every base object regardless.
start_overlay_case bob
write_json "$OVERLAY_FILE/mcp.overlay.json" '{"mcpServers":null}'
run_overlay_case bob
assert_overlay_installed 'null empty-object overlay'

# 6. The other half of that exemption has no instance in any base file, so it is the
#    one rule a fixture has to construct. Without it an implementation that drops the
#    `non-empty` qualifier passes everything else here, and breaks every host the day a
#    base file seeds a key with `[]`.
exempt_repo="$tmpdir/exempt-repo"
mkdir -p "$exempt_repo/docs"
cp -pR "$REPO/install.sh" "$REPO/content" "$REPO/agents" "$exempt_repo/"
cp -pR "$REPO/docs/licenses" "$exempt_repo/docs/"
exempt_base="$exempt_repo/agents/claude/shared/settings.base.json"
jq '.permissions.allow = []' "$BASE_SETTINGS" >"$exempt_base"
# The planted key has to be genuinely empty in the copy, or the case proves nothing.
[[ "$(jq -c '.permissions.allow' "$exempt_base")" == '[]' ]] ||
	fail "exempt fixture must plant an empty array"
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" \
	'{"permissions":{"allow":["Read(/tmp/**)"]}}'
run_overlay_case claude "$exempt_repo/install.sh"
assert_overlay_installed 'empty-array exemption'
assert_json_value "$OVERLAY_DEST/claude/settings.json" '.permissions.allow[0]' \
	'Read(/tmp/**)'

# --- A refused overlay withholds one destination set, not the run (ADR 0049) ----------
#
# Every destination below is produced by a *successful* install before anything is
# planted into it. `prune_removed` returns immediately when the destination has no
# `.agent-config-manifest`, and that file is written only by a completed `finish_agent`
# — so a hand-built destination leaves the retention rule unexercised, and a "the file
# survived" assertion passes against a build that never retains anything. A clobbered
# deployment has to be built this way in any case, since ADR 0043 makes the installer
# refuse to produce one.

CLOBBERING_OVERLAY='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}]}}'

# 11. The residual #126 reports: a host clobbered by the pre-ADR-0043 merge. Reproduce
#     that file exactly as the old installer produced it — `.[0] * .[1]` of base and
#     overlay — deploy it over a real install, then refuse against it.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"kept"}}'
run_overlay_case claude
assert_overlay_installed 'clobbered deployment setup'
printf '%s\n' "$CLOBBERING_OVERLAY" >"$tmpdir/clobbering-overlay.json"
jq -s '.[0] * .[1]' "$BASE_SETTINGS" "$tmpdir/clobbering-overlay.json" \
	>"$OVERLAY_DEST/claude/settings.json"
# The planted file must really be missing the guards, or the case proves nothing.
[[ "$(jq '.hooks.PreToolUse | length' "$OVERLAY_DEST/claude/settings.json")" == 1 ]] ||
	fail 'clobbered fixture must carry one hook instead of the base set'
cp "$OVERLAY_DEST/claude/settings.json" "$tmpdir/clobbered-planted.json"

write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case claude
assert_overlay_refused 'clobbered deployment reported'
# The distinct half: the overlay rejection names what *would* be erased, and this names
# what the file the agent actually loads is missing right now. Without the deployed-file
# comparison the second message does not exist and this reddens.
assert_stream_contains "$OVERLAY_ERR" 'is missing protected values' 'clobbered deployment reported'
assert_stream_contains "$OVERLAY_ERR" '.agent-config-backups' 'clobbered deployment reported'
assert_stream_contains "$OVERLAY_ERR" 'would erase values' 'clobbered deployment reported'
# Reported, never repaired: the deployed file is byte-identical to what was planted.
assert_same_file "$tmpdir/clobbered-planted.json" "$OVERLAY_DEST/claude/settings.json"
assert_line "$OVERLAY_DEST/claude/.agent-config-manifest" 'settings.json'
assert_stream_contains "$OVERLAY_ERR" 'private overlay(s) were refused' \
	'clobbered deployment reported'

# 12. Idempotent over a retained deployment: a second refused run changes nothing.
cp "$OVERLAY_ERR" "$tmpdir/refusal-first.err"
run_overlay_case claude
assert_overlay_refused 'refused run is idempotent'
assert_same_file "$tmpdir/clobbered-planted.json" "$OVERLAY_DEST/claude/settings.json"
assert_same_file "$tmpdir/refusal-first.err" "$OVERLAY_ERR"

# 13. The documented route back. Fix the overlay, re-run, and the managed-path code that
#     has always owned the file replaces it and keeps the clobbered one.
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"kept"}}'
run_overlay_case claude
assert_overlay_installed 'clobbered deployment repaired'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.hooks' \
	'clobbered deployment repaired'
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" \
	'.permissions.deny' 'clobbered deployment repaired'
assert_json_value "$OVERLAY_DEST/claude/settings.json" '.env.AGENT_CONFIG_TEST' kept
assert_tree_contains "$OVERLAY_DEST/claude/.agent-config-backups" '"command": "true"'

# 14. The freeze itself, which is what #126's reframing is about. A refused Claude
#     overlay must not cost that agent its skills, instructions or shared content, and
#     under `--agent all` must not cost the later agents their whole install.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case all
assert_overlay_refused 'refusal does not freeze the tree'
assert_file "$OVERLAY_DEST/claude/CLAUDE.md"
assert_file "$OVERLAY_DEST/claude/skills/preflight/SKILL.md"
assert_file "$OVERLAY_DEST/claude/languages/bash.md"
assert_file "$OVERLAY_DEST/codex/config.toml"
assert_file "$OVERLAY_DEST/codex/skills/preflight/SKILL.md"
assert_file "$OVERLAY_DEST/bob/settings.json"
assert_file "$OVERLAY_DEST/bob/mcp_settings.json"

# 15. The empty destination converges on the base rather than staying unguarded. Run 14
#     left this destination filled, so re-running it is the convergence half: the file is
#     byte-identical and is now reported as base-alone, not as carrying every value —
#     without that verdict the operator's own configuration would read as being in order.
cp "$OVERLAY_DEST/claude/settings.json" "$tmpdir/base-filled.json"
run_overlay_case all
assert_overlay_refused 'empty destination converges'
assert_same_file "$tmpdir/base-filled.json" "$OVERLAY_DEST/claude/settings.json"
assert_stream_contains "$OVERLAY_ERR" 'is the base alone' 'empty destination converges'
assert_stream_lacks "$OVERLAY_ERR" 'has every array and object' 'empty destination converges'
# The refusal unlinks the merged temp file, so the fill has to allocate a fresh 0600 one
# rather than re-creating it by redirection, which would take the umask. `payload_differs`
# compares content and the executable bit only, so a widened mode would never converge
# back. `-perm -044` is both group- and other-read, and is portable to BSD find.
[[ -z "$(find "$OVERLAY_DEST/claude/settings.json" -perm -044 -print)" ]] ||
	fail 'base-filled settings.json must not be group- or world-readable'

# 16. One merged document, two destinations. `agents/bob/shared/mcp.json` ships
#     `mcpServers` as `{}`, which is unprotected, so no in-repo overlay can be refused
#     there and this rule has to be constructed. It is the one place a per-path
#     withhold is observable: retaining `mcp.json` and forgetting `mcp_settings.json`
#     leaves the second in the old manifest and absent from the new one, and
#     `prune_removed` deletes it.
bob_repo="$tmpdir/bob-repo"
mkdir -p "$bob_repo/docs"
cp -pR "$REPO/install.sh" "$REPO/content" "$REPO/agents" "$bob_repo/"
cp -pR "$REPO/docs/licenses" "$bob_repo/docs/"
bob_mcp_base="$bob_repo/agents/bob/shared/mcp.json"
jq '.mcpServers = {"seeded":{"command":"true"}}' "$REPO/agents/bob/shared/mcp.json" \
	>"$bob_mcp_base"
# The seeded container must be genuinely non-empty, or the overlay below is exempt and
# the case tests nothing.
[[ "$(jq -r '.mcpServers.seeded.command' "$bob_mcp_base")" == 'true' ]] ||
	fail 'bob fixture must seed a non-empty mcpServers object'

start_overlay_case bob
run_overlay_case bob "$bob_repo/install.sh"
assert_overlay_installed 'bob two-destination setup'
assert_file "$OVERLAY_DEST/bob/mcp.json"
assert_file "$OVERLAY_DEST/bob/mcp_settings.json"
cp "$OVERLAY_DEST/bob/mcp.json" "$tmpdir/bob-mcp-before.json"

write_json "$OVERLAY_FILE/mcp.overlay.json" '{"mcpServers":null}'
run_overlay_case bob "$bob_repo/install.sh"
assert_overlay_refused 'bob two-destination refusal'
assert_file "$OVERLAY_DEST/bob/mcp.json"
assert_file "$OVERLAY_DEST/bob/mcp_settings.json"
assert_same_file "$tmpdir/bob-mcp-before.json" "$OVERLAY_DEST/bob/mcp.json"
assert_same_file "$tmpdir/bob-mcp-before.json" "$OVERLAY_DEST/bob/mcp_settings.json"
assert_line "$OVERLAY_DEST/bob/.agent-config-manifest" 'mcp.json'
assert_line "$OVERLAY_DEST/bob/.agent-config-manifest" 'mcp_settings.json'

# 17. The same set, half populated. The fill is evaluated over the whole set, so a
#     destination holding one of the two is not "empty" and neither path is rewritten —
#     filling only the absent one would leave one document as two differing files.
remove_dest_file="$OVERLAY_DEST/bob/mcp_settings.json"
rm "$remove_dest_file"
run_overlay_case bob "$bob_repo/install.sh"
assert_overlay_refused 'bob half-populated set'
assert_same_file "$tmpdir/bob-mcp-before.json" "$OVERLAY_DEST/bob/mcp.json"
assert_not_file "$remove_dest_file"

# --- Every guarded jq call fails closed (ADR 0049 rule 1) ------------------------------
#
# Testing a function's status at the call site suppresses `set -e` for its whole body,
# so each fallible jq call inside the merge needs its own guard. A globally failing jq
# stops at the merge and can never reach either protected-set comparison, so a build
# leaving both bare would pass such a case. This shim fails one selected invocation,
# chosen by argument shape, and delegates everything else to the real binary.
jq_shim_dir="$tmpdir/jq-shim"
mkdir -p "$jq_shim_dir"
real_jq="$(command -v jq)"
cat >"$jq_shim_dir/jq" <<'SHIM'
#!/usr/bin/env bash
set -u
shape=other
for arg in "$@"; do
	case $arg in
	'.[0] * .[1]') shape=merge ;;
	*@tsv*) shape=shape ;;
	-rn) shape=compare ;;
	-S) shape=normalize ;;
	esac
done
if [[ $shape == other && $# -eq 2 && $1 == '.' ]]; then
	shape=render
fi
if [[ $shape == "${AGENT_CONFIG_TEST_JQ_FAIL:-}" ]]; then
	count=0
	if [[ -f $AGENT_CONFIG_TEST_JQ_COUNT ]]; then
		count=$(cat "$AGENT_CONFIG_TEST_JQ_COUNT")
	fi
	count=$((count + 1))
	printf '%s\n' "$count" >"$AGENT_CONFIG_TEST_JQ_COUNT"
	if [[ $count -eq ${AGENT_CONFIG_TEST_JQ_NTH:-1} ]]; then
		printf 'jq-shim: forced failure (%s #%s)\n' "$shape" "$count" >&2
		exit 3
	fi
fi
exec "$AGENT_CONFIG_TEST_REAL_JQ" "$@"
SHIM
chmod +x "$jq_shim_dir/jq"

run_overlay_case_jq() { # agent fail-shape [nth]
	OVERLAY_STATUS=0
	rm -f "$OVERLAY_ROOT/jq-count"
	PATH="$jq_shim_dir:$PATH" \
		AGENT_CONFIG_TEST_REAL_JQ="$real_jq" \
		AGENT_CONFIG_TEST_JQ_FAIL="$2" \
		AGENT_CONFIG_TEST_JQ_NTH="${3:-1}" \
		AGENT_CONFIG_TEST_JQ_COUNT="$OVERLAY_ROOT/jq-count" \
		AGENT_CONFIG_HOST=test-host \
		AGENT_CONFIG_PRIVATE_DIR="$OVERLAY_PRIVATE" \
		CLAUDE_CONFIG_DIR="$OVERLAY_DEST/claude" \
		CODEX_CONFIG_DIR="$OVERLAY_DEST/codex" \
		BOB_CONFIG_DIR="$OVERLAY_DEST/bob" \
		./install.sh --agent "$1" \
		>"$OVERLAY_OUT" 2>"$OVERLAY_ERR" || OVERLAY_STATUS=$?
}

# 18. The default configuration — no overlay at all — renders the base through jq, and
#     an unguarded failure there leaves a truncated file that passes
#     `install_managed_path`'s missing-source test and deploys as a zero-byte
#     settings.json on a green run.
start_overlay_case claude
run_overlay_case_jq claude render
assert_overlay_refused 'no-overlay render fails closed'
assert_stream_contains "$OVERLAY_ERR" 'could not read base settings' \
	'no-overlay render fails closed'
assert_not_file "$OVERLAY_DEST/claude/settings.json"

# 19. The merge itself.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case_jq claude merge
assert_overlay_refused 'merge failure fails closed'
assert_stream_contains "$OVERLAY_ERR" 'could not merge private overlay' \
	'merge failure fails closed'
assert_stream_lacks "$OVERLAY_ERR" 'would erase values' 'merge failure fails closed'
assert_not_file "$OVERLAY_DEST/claude/settings.json"

# 20. The merge-result comparison. `erased_base_paths` reports "nothing erased" and "I
#     could not tell" with the same empty stdout, so an unguarded failure here reads as
#     a clean overlay and deploys the merged result.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case_jq claude compare 1
assert_overlay_refused 'overlay comparison fails closed'
assert_stream_contains "$OVERLAY_ERR" 'could not compare the merged result' \
	'overlay comparison fails closed'
assert_stream_lacks "$OVERLAY_ERR" 'would erase values' 'overlay comparison fails closed'
assert_not_file "$OVERLAY_DEST/claude/settings.json"

# 21. The deployed-file comparison, which is reachable only after the first one has
#     succeeded and returned a refusal — which is why a globally failing jq cannot get
#     here and this case needs the shim's occurrence counter.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'deployed comparison setup'
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case_jq claude compare 2
assert_overlay_refused 'deployed comparison fails closed'
assert_stream_contains "$OVERLAY_ERR" 'would erase values' 'deployed comparison fails closed'
# The diagnostic, not just the exit status: `report_deployed_state` runs outside a tested
# context, so an unguarded failure there aborts under `set -e` anyway. Both builds fail
# the run, and only this message distinguishes the guarded one.
assert_stream_contains "$OVERLAY_ERR" 'could not compare' 'deployed comparison fails closed'
assert_stream_lacks "$OVERLAY_ERR" 'has every array and object' 'deployed comparison fails closed'

# 22. The refusal is no longer the last thing on the screen, so the summary that replaces
#     it is emitted from the EXIT trap. Refuse Claude, then hard-fail Codex on a missing
#     source: an end-of-run summary would be preempted and the operator would see only
#     the second failure.
preempt_repo="$tmpdir/preempt-repo"
mkdir -p "$preempt_repo/docs"
cp -pR "$REPO/install.sh" "$REPO/content" "$REPO/agents" "$preempt_repo/"
cp -pR "$REPO/docs/licenses" "$preempt_repo/docs/"
rm "$preempt_repo/agents/codex/shared/AGENTS.md"
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case all "$preempt_repo/install.sh"
assert_overlay_refused 'summary survives a later hard failure'
assert_stream_contains "$OVERLAY_ERR" 'missing source' 'summary survives a later hard failure'
assert_stream_contains "$OVERLAY_ERR" 'private overlay(s) were refused' \
	'summary survives a later hard failure'

# 23. The one failure the design treats as a verdict rather than an error: a deployed
#     file that will not parse. Nothing else fails if this branch stops working — the
#     run continues either way — so without a case it can rot silently.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'unparseable deployment setup'
write_text "$OVERLAY_DEST/claude/settings.json" '{"hooks": '
cp "$OVERLAY_DEST/claude/settings.json" "$tmpdir/unparseable.json"
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case claude
assert_overlay_refused 'unparseable deployment'
assert_stream_contains "$OVERLAY_ERR" 'could not be read as JSON' 'unparseable deployment'
# Reported, not repaired, and not guessed at.
assert_same_file "$tmpdir/unparseable.json" "$OVERLAY_DEST/claude/settings.json"
assert_stream_lacks "$OVERLAY_ERR" 'has every array and object' 'unparseable deployment'

# 24. A destination path that is a symlink is occupied, so it is retained and listed as
#     kept — and its target is not the installer's to vouch for. Saying "nothing is
#     deployed" here would contradict the kept list in the same output.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'symlinked deployment setup'
mv "$OVERLAY_DEST/claude/settings.json" "$OVERLAY_ROOT/elsewhere.json"
ln -s "$OVERLAY_ROOT/elsewhere.json" "$OVERLAY_DEST/claude/settings.json"
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case claude
assert_overlay_refused 'symlinked deployment'
assert_stream_contains "$OVERLAY_ERR" 'is a symlink' 'symlinked deployment'
assert_stream_lacks "$OVERLAY_ERR" 'no file is deployed at' 'symlinked deployment'
[[ -L "$OVERLAY_DEST/claude/settings.json" ]] ||
	fail 'symlinked deployment: the symlink must be left in place'

# 25. The absent half of a half-populated destination set reports as absent rather than
#     being filled — case 17 leaves exactly that state, and nothing there reads the
#     message it produces.
start_overlay_case bob
run_overlay_case bob "$bob_repo/install.sh"
assert_overlay_installed 'absent-path verdict setup'
rm "$OVERLAY_DEST/bob/mcp_settings.json"
write_json "$OVERLAY_FILE/mcp.overlay.json" '{"mcpServers":null}'
run_overlay_case bob "$bob_repo/install.sh"
assert_overlay_refused 'absent-path verdict'
assert_stream_contains "$OVERLAY_ERR" 'no file is deployed at' 'absent-path verdict'
assert_not_file "$OVERLAY_DEST/bob/mcp_settings.json"
# The tail summary lists this absent path too, so its header has to be true of an absent
# entry. An operator who reads only the tail must not be told a missing file is intact.
assert_stream_contains "$OVERLAY_ERR" 'these paths were left untouched' 'absent-path verdict'
assert_stream_lacks "$OVERLAY_ERR" 'deployed paths were kept' 'absent-path verdict'

# 26. The base normalization behind the base-alone comparison is guarded like every other
#     jq call, and is the one the shim's `normalize` shape reaches.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'normalize guard setup'
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case_jq claude normalize 1
assert_overlay_refused 'normalize guard fails closed'
assert_stream_contains "$OVERLAY_ERR" 'could not read base settings' \
	'normalize guard fails closed'
assert_stream_lacks "$OVERLAY_ERR" 'has every array and object' 'normalize guard fails closed'

# 26b. A directory occupying a destination path is occupied, not bare. It is retained and
#      listed like any other withheld path, so reporting "no file is deployed" would tell
#      the operator the destination is empty while something sits on it.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'directory at the destination setup'
rm "$OVERLAY_DEST/claude/settings.json"
mkdir "$OVERLAY_DEST/claude/settings.json"
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case claude
assert_overlay_refused 'directory at the destination'
assert_stream_contains "$OVERLAY_ERR" 'a directory occupies' 'directory at the destination'
assert_stream_lacks "$OVERLAY_ERR" 'no file is deployed at' 'directory at the destination'
[[ -d "$OVERLAY_DEST/claude/settings.json" ]] ||
	fail 'directory at the destination: the directory must be left in place'
assert_line "$OVERLAY_DEST/claude/.agent-config-manifest" 'settings.json'

# 27. The honest scope of the clean verdict. ADR 0043's check covers non-empty base
#     arrays and objects, so a deployed file that dropped a scalar or emptied an object
#     passes it. Saying it carries every value the base *defines* would be a definite
#     statement that is false, and an operator would have an affirmative reason to stop
#     looking; the wording says "protected", and this case is what holds it there.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case claude
assert_overlay_installed 'unprotected scalar loss setup'
jq '.env = {} | del(.cleanupPeriodDays)' "$BASE_SETTINGS" \
	>"$OVERLAY_DEST/claude/settings.json"
write_json "$OVERLAY_FILE/settings.overlay.json" "$CLOBBERING_OVERLAY"
run_overlay_case claude
assert_overlay_refused 'unprotected scalar loss'
assert_stream_contains "$OVERLAY_ERR" 'has every array and object' \
	'unprotected scalar loss'
assert_stream_lacks "$OVERLAY_ERR" 'is missing protected values' 'unprotected scalar loss'
# And says so: the base's telemetry and MCP hardening are scalars, so an unqualified
# affirmation here would be a clean bill for a file that lost them.
assert_stream_contains "$OVERLAY_ERR" 'Base scalars are outside this check' \
	'unprotected scalar loss'

# --- An overlay is exactly one JSON object (ADR 0052) ---------------------------------
#
# Four shapes, one verdict each, all refused before the merge runs. The messages are
# asserted individually because the whole point of the record is that the operator can
# tell which of the four they have; a build collapsing them into one message passes an
# exit-status-only case.
#
# Every case also asserts the absence of jq's own wording. `cannot be multiplied` is what
# three of these four printed before, naming the base's contents and no remedy, and
# nothing else in the suite would notice its return.

# 28. The reported defect. Two concatenated objects: `jq -s`'s `.[1]` is the first, so the
#     second used to be discarded on a green run. The destination is empty, so ADR 0049's
#     rule 4 fills it from the base — and neither document may appear in it. Asserting the
#     absence of document *one* is what separates a refusal from the old behaviour, which
#     applied it.
start_overlay_case claude
write_text "$OVERLAY_FILE/settings.overlay.json" \
	'{"env":{"AGENT_CONFIG_TEST":"first"}}{"env":{"AGENT_CONFIG_TEST":"second"}}'
run_overlay_case claude
assert_overlay_refused 'multi-document overlay'
assert_stream_contains "$OVERLAY_ERR" "$OVERLAY_FILE/settings.overlay.json" \
	'multi-document overlay'
assert_stream_contains "$OVERLAY_ERR" 'contains 2 JSON values, not one' \
	'multi-document overlay'
assert_stream_lacks "$OVERLAY_ERR" 'cannot be multiplied' 'multi-document overlay'
assert_stream_lacks "$OVERLAY_OUT" 'applied private overlay' 'multi-document overlay'
# Document *one* must not be applied either. That is what separates a refusal from the
# old behaviour, which merged it and reported success.
assert_json_value "$OVERLAY_DEST/claude/settings.json" \
	'.env.AGENT_CONFIG_TEST // "absent"' absent
assert_json_equal "$OVERLAY_DEST/claude/settings.json" "$BASE_SETTINGS" '.hooks' \
	'multi-document overlay'
assert_stream_contains "$OVERLAY_ERR" 'private overlay(s) were refused' \
	'multi-document overlay'
# The base fill reaches this destination through a new refusal path, so it has to allocate
# its own 0600 temp rather than inherit the umask, exactly as case 15 requires of the other.
[[ -z "$(find "$OVERLAY_DEST/claude/settings.json" -perm -044 -print)" ]] ||
	fail 'multi-document overlay: base-filled settings.json must not be group- or world-readable'

# 29. A zero-byte overlay. `write_json` appends a newline, so the file is created bare.
start_overlay_case claude
mkdir -p "$OVERLAY_FILE"
: >"$OVERLAY_FILE/settings.overlay.json"
run_overlay_case claude
assert_overlay_refused 'empty overlay'
assert_stream_contains "$OVERLAY_ERR" "$OVERLAY_FILE/settings.overlay.json" 'empty overlay'
assert_stream_contains "$OVERLAY_ERR" 'contains no JSON value' 'empty overlay'
assert_stream_lacks "$OVERLAY_ERR" 'cannot be multiplied' 'empty overlay'

# 30. Whitespace only. A size test would pass this file through to the same jq abort, so
#     it is a case of its own rather than a variant of 29.
start_overlay_case claude
write_text "$OVERLAY_FILE/settings.overlay.json" '   '
run_overlay_case claude
assert_overlay_refused 'whitespace-only overlay'
assert_stream_contains "$OVERLAY_ERR" 'contains no JSON value' 'whitespace-only overlay'
assert_stream_lacks "$OVERLAY_ERR" 'cannot be multiplied' 'whitespace-only overlay'

# 31. One value, wrong type. The array is what the issue reports; `null` is the shape that
#     produced the same message as the empty file, so both are pinned.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '[]'
run_overlay_case claude
assert_overlay_refused 'array overlay'
assert_stream_contains "$OVERLAY_ERR" 'is a JSON array, not an object' 'array overlay'
assert_stream_lacks "$OVERLAY_ERR" 'cannot be multiplied' 'array overlay'

start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" 'null'
run_overlay_case claude
assert_overlay_refused 'null overlay'
assert_stream_contains "$OVERLAY_ERR" 'is a JSON null, not an object' 'null overlay'
assert_stream_lacks "$OVERLAY_ERR" 'cannot be multiplied' 'null overlay'

# 32. Not JSON at all. The remedy has to carry the way to find *where* it stops parsing,
#     because the diagnostic deliberately does not relay jq's own parse error.
start_overlay_case claude
write_text "$OVERLAY_FILE/settings.overlay.json" '{"env": '
run_overlay_case claude
assert_overlay_refused 'unparseable overlay'
assert_stream_contains "$OVERLAY_ERR" 'is not valid JSON' 'unparseable overlay'
assert_stream_contains "$OVERLAY_ERR" "jq . $OVERLAY_FILE/settings.overlay.json" \
	'unparseable overlay'

# 33. The refusal takes ADR 0049's terms rather than aborting. Built on a destination
#     produced by a *real* install: `prune_removed` returns early where there is no
#     `.agent-config-manifest`, so a hand-built destination leaves rule 3 unexercised and
#     a "the file survived" assertion would pass against a build that retains nothing.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"kept"}}'
run_overlay_case claude
assert_overlay_installed 'shape refusal over a deployment setup'
cp "$OVERLAY_DEST/claude/settings.json" "$tmpdir/shape-deployed.json"
write_text "$OVERLAY_FILE/settings.overlay.json" '{"env":{"A":"1"}}{"env":{"B":"2"}}'
run_overlay_case claude
assert_overlay_refused 'shape refusal over a deployment'
assert_same_file "$tmpdir/shape-deployed.json" "$OVERLAY_DEST/claude/settings.json"
# The manifest entry is the only thing between a withheld path and `prune_removed`.
assert_line "$OVERLAY_DEST/claude/.agent-config-manifest" 'settings.json'
assert_stream_contains "$OVERLAY_ERR" 'has every array and object' \
	'shape refusal over a deployment'
assert_stream_contains "$OVERLAY_ERR" 'these paths were left untouched' \
	'shape refusal over a deployment'

# 34. And is idempotent: a second refused run changes neither the file nor the report.
cp "$OVERLAY_ERR" "$tmpdir/shape-refusal-first.err"
run_overlay_case claude
assert_overlay_refused 'shape refusal is idempotent'
assert_same_file "$tmpdir/shape-deployed.json" "$OVERLAY_DEST/claude/settings.json"
assert_same_file "$tmpdir/shape-refusal-first.err" "$OVERLAY_ERR"

# 35. The behaviour change ADR 0052 is really buying: these four shapes used to `exit 1`
#     inside the merge, which under `--agent all` cost the operator every agent. Claude is
#     first, so a malformed Claude overlay is the case that used to install nothing at all.
start_overlay_case claude
write_text "$OVERLAY_FILE/settings.overlay.json" '{"env":{"A":"1"}}{"env":{"B":"2"}}'
run_overlay_case all
assert_overlay_refused 'malformed overlay does not freeze the run'
assert_file "$OVERLAY_DEST/claude/CLAUDE.md"
assert_file "$OVERLAY_DEST/claude/skills/preflight/SKILL.md"
assert_file "$OVERLAY_DEST/codex/config.toml"
assert_file "$OVERLAY_DEST/bob/settings.json"
assert_file "$OVERLAY_DEST/bob/mcp_settings.json"

# 36. The shape check is a jq call like any other, so it fails closed (ADR 0049 rule 1).
#     A build reading its failure as "the overlay is fine" would merge an unvalidated
#     overlay, which is the defect this section exists to close.
start_overlay_case claude
write_json "$OVERLAY_FILE/settings.overlay.json" '{"env":{"AGENT_CONFIG_TEST":"first"}}'
run_overlay_case_jq claude shape
assert_overlay_refused 'shape check fails closed'
assert_stream_contains "$OVERLAY_ERR" 'is not valid JSON' 'shape check fails closed'
assert_stream_lacks "$OVERLAY_OUT" 'applied private overlay' 'shape check fails closed'
# An overlay the check could not read must not reach the merge.
assert_json_value "$OVERLAY_DEST/claude/settings.json" \
	'.env.AGENT_CONFIG_TEST // "absent"' absent

printf 'install-test: ok\n'
