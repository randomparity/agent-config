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

printf 'install-test: ok\n'
