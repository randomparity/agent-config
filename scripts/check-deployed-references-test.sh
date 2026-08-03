#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-deployed-references.sh"

if [[ ! -x "$CHECKER" ]]; then
	printf 'checker does not exist: %s\n' "$CHECKER" >&2
	exit 127
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/deployed-references-test.XXXXXX")"
FIXTURE="$SCRATCH/repo"

cleanup() {
	case "$SCRATCH" in
	"${TMPDIR:-/tmp}"/deployed-references-test.*) rm -R "$SCRATCH" ;;
	*) printf 'deployed-references-test: refusing cleanup: %s\n' "$SCRATCH" >&2 ;;
	esac
}
trap cleanup EXIT

reset_fixture() {
	rm -R "$FIXTURE" 2>/dev/null || :
	mkdir -p \
		"$FIXTURE/content/skills/example" \
		"$FIXTURE/agents/claude/shared" \
		"$FIXTURE/agents/codex/shared" \
		"$FIXTURE/agents/bob/shared"
	printf 'portable text\n' >"$FIXTURE/content/skills/example/SKILL.md"
	printf 'portable text\n' >"$FIXTURE/agents/claude/shared/CLAUDE.md"
	printf 'portable text\n' >"$FIXTURE/agents/codex/shared/AGENTS.md"
	printf 'portable text\n' >"$FIXTURE/agents/bob/shared/AGENTS.md"
}

assert_passes() {
	local name="$1" relative="$2" content="$3"
	reset_fixture
	mkdir -p "$(dirname "$FIXTURE/$relative")"
	printf '%s\n' "$content" >"$FIXTURE/$relative"
	if ! "$CHECKER" "$FIXTURE" >"$SCRATCH/output" 2>&1; then
		printf 'not ok - %s should pass\n' "$name" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
}

assert_fails() {
	local name="$1" class="$2" relative="$3" content="$4"
	reset_fixture
	mkdir -p "$(dirname "$FIXTURE/$relative")"
	printf '%s\n' "$content" >"$FIXTURE/$relative"
	if "$CHECKER" "$FIXTURE" >"$SCRATCH/output" 2>&1; then
		printf 'not ok - %s should fail\n' "$name" >&2
		exit 1
	fi
	if ! rg -q "deployed-references: $class:" "$SCRATCH/output"; then
		printf 'not ok - %s should report %s\n' "$name" "$class" >&2
		sed -n '1,20p' "$SCRATCH/output" >&2
		exit 1
	fi
}

# The deployment boundary, from both sides. `stage_skills` filters `testdata`
# entries out of `content/skills` and out of nothing else, so a fixture there is
# never deployed and cannot violate a deployment rule — while the same content
# under `agents/*/shared` installs verbatim and must still be caught. Without the
# second case the exclusion could be widened to every scan root with this suite
# green, which is how the gate would go blind over a path that really does ship.
assert_passes 'testdata fixture under content/skills is not deployed' \
	'content/skills/example/testdata/fixture.md' 'Governed by ADR 0019.'
assert_fails 'testdata under agents/ still deploys' bare-adr \
	'agents/bob/shared/rules/testdata/fixture.md' 'Governed by ADR 0019.'

assert_fails 'bare ADR' bare-adr \
	'content/skills/example/SKILL.md' 'Governed by ADR 0019.'
assert_fails 'bare ADR with hash' bare-adr \
	'content/skills/example/SKILL.md' 'Governed by ADR #0019.'
assert_fails 'bare source issue' bare-issue \
	'agents/claude/shared/CLAUDE.md' 'This closes issue #49.'
assert_fails 'stale epic spec' concrete-relative-path \
	'content/skills/example/SKILL.md' \
	'docs/superpowers/specs/2026-07-19-epic-command-design.md'
assert_fails 'dot-prefixed stale spec' concrete-relative-path \
	'content/skills/example/SKILL.md' \
	'./docs/superpowers/specs/2026-07-19-epic-command-design.md'
assert_fails 'parent-prefixed stale record' concrete-relative-path \
	'content/skills/example/SKILL.md' '../docs/adr/0019-source-local.md'
assert_fails 'mixed concrete plan path' concrete-relative-path \
	'agents/codex/shared/AGENTS.md' \
	'docs/superpowers/plans/template/YYYY-MM-DD/actual-plan.md'
assert_fails 'unmarked concrete ADR path' concrete-relative-path \
	'agents/bob/shared/AGENTS.md' 'Read docs/adr/0019-source-local.md.'
assert_fails 'unmarked concrete debt path' concrete-relative-path \
	'content/skills/example/SKILL.md' 'Read docs/debt/0007-source-local.md.'
assert_fails 'canonical non-Markdown prompt' bare-adr \
	'content/skills/example/agents/openai.yaml' 'prompt: Follow ADR 0042.'

assert_passes 'record directory' \
	'content/skills/example/SKILL.md' 'Read docs/adr/ before review.'
assert_passes 'marked target record path' \
	'content/skills/example/SKILL.md' \
	'Read the target-repository path: docs/adr/README.md.'
assert_passes 'record template' \
	'content/skills/example/SKILL.md' 'Write docs/debt/NNNN-<slug>.md.'
assert_passes 'dated plan template' \
	'content/skills/example/SKILL.md' \
	'Write docs/superpowers/plans/YYYY-MM-DD-<feature>.md.'
assert_passes 'spec glob' \
	'content/skills/example/SKILL.md' 'Review docs/superpowers/specs/*.md.'
assert_passes 'stable issue URL' \
	'content/skills/example/SKILL.md' \
	'https://github.com/randomparity/agent-config/issues/14'
assert_passes 'descriptive stable ADR link' \
	'content/skills/example/SKILL.md' \
	'[permission decision](https://github.com/example/repo/blob/abc/docs/adr/0019-name.md)'
assert_passes 'decision-record engine target operand' \
	'content/skills/decision-records/assets/check.sh' \
	'file=docs/adr/README.md'
assert_fails 'bare ADR inside record engine' bare-adr \
	'content/skills/decision-records/assets/check.sh' \
	'# Governed by ADR 0019.'
assert_fails 'concrete plan path inside record engine' concrete-relative-path \
	'content/skills/decision-records/assets/check.sh' \
	'# docs/superpowers/plans/source-local.md'
assert_fails 'unmarked record path in another shell asset' concrete-relative-path \
	'content/skills/example/scripts/check.sh' \
	'file=docs/adr/README.md'

reset_fixture
printf 'prefix\0Governed by ADR 0019.\0suffix\n' \
	>"$FIXTURE/content/skills/example/binary.dat"
if ! "$CHECKER" "$FIXTURE" >"$SCRATCH/output" 2>&1; then
	printf 'not ok - binary payload should be ignored\n' >&2
	sed -n '1,20p' "$SCRATCH/output" >&2
	exit 1
fi

printf 'deployed-references-test: ok\n'
