set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

test_public_safety_command := "./scripts/check-public-safety-test.sh"

default:
  just --list

setup:
  AGENT_CONFIG_SETUP_HOOKS=1 ./install-tools.sh

hooks:
  prek install

tools-check:
  ./install-tools.sh --check

records:
  #!/usr/bin/env bash
  set -euo pipefail
  ./.github/scripts/check-records-test.sh
  RECORD_PROFILES="adr debt" ./.github/scripts/check-records.sh
  shared_assets="check-records.sh check-records-test.sh migrate-records.sh"
  shared_assets="$shared_assets profiles/adr.sh profiles/debt.sh records.yml"
  for asset in $shared_assets; do
    root_asset=".github/scripts/$asset"
    skill_asset="content/skills/decision-records/assets/$asset"
    if ! cmp -s "$root_asset" "$skill_asset"; then
      echo "record gate mismatch: $skill_asset differs from $root_asset" >&2
      exit 1
    fi
  done

# A `testdata/` suite is excluded from the installed payload, never from the
# gates: each glob below names it explicitly so it stays linted, formatted and
# run from its new path (ADR 0025).
lint:
  shellcheck install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh \
    .github/scripts/*.sh .github/scripts/profiles/*.sh \
    content/skills/issue/scripts/*.sh \
    content/skills/issue/scripts/testdata/*.sh \
    content/skills/brainstorming/scripts/*.sh \
    content/skills/brainstorming/scripts/testdata/*.sh \
    content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh \
    content/skills/github-tracking/assets/testdata/*.sh
  # Named one by one, not by glob: these three are extensionless, so no `*.sh`
  # pattern reaches them and they sat outside every gate until #74 put new logic
  # in sdd-workspace.
  shellcheck content/skills/subagent-driven-development/scripts/sdd-workspace \
    content/skills/subagent-driven-development/scripts/task-brief \
    content/skills/subagent-driven-development/scripts/review-package \
    content/skills/subagent-driven-development/scripts/testdata/*.sh
  shellcheck agents/claude/shared/statusline.sh \
    content/skills/systematic-debugging/find-polluter.sh
  shellcheck content/skills/preflight/scripts/detect-host-architecture \
    content/skills/preflight/scripts/resolve-architecture-context \
    content/skills/preflight/scripts/testdata/*.sh

# The brainstorming scripts and the suite that exercises them take `-i 2`. The
# scripts are vendored two-space-indented (ADR 0005, under which an upstream
# update is a deliberate re-vendor that reviews the upstream diff against local
# adaptations), so reformatting them to the repository default would cost that
# diff for nothing. ADR 0025 gave the suite `-i 2` for the same reason (#57).
format-check:
  shfmt -d install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
  shfmt -i 2 -d .github/scripts/*.sh .github/scripts/profiles/*.sh
  shfmt -d content/skills/issue/scripts/*.sh \
    content/skills/issue/scripts/testdata/*.sh
  shfmt -i 2 -d content/skills/brainstorming/scripts/*.sh \
    content/skills/brainstorming/scripts/testdata/*.sh
  shfmt -d content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh \
    content/skills/github-tracking/assets/testdata/*.sh
  # Repository default, not `-i 2`: these are first-party, so the ADR 0005
  # re-vendor argument that earns the brainstorming carve-out does not apply.
  shfmt -d content/skills/subagent-driven-development/scripts/sdd-workspace \
    content/skills/subagent-driven-development/scripts/task-brief \
    content/skills/subagent-driven-development/scripts/review-package \
    content/skills/subagent-driven-development/scripts/testdata/*.sh
  # These existing first-party sources use two-space indentation; keeping that
  # style avoids an unrelated full-file reformat while bringing them under the gate.
  shfmt -i 2 -d agents/claude/shared/statusline.sh \
    content/skills/systematic-debugging/find-polluter.sh
  shfmt -d content/skills/preflight/scripts/detect-host-architecture \
    content/skills/preflight/scripts/resolve-architecture-context \
    content/skills/preflight/scripts/testdata/*.sh

format:
  shfmt -w install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
  shfmt -i 2 -w .github/scripts/*.sh .github/scripts/profiles/*.sh
  shfmt -w content/skills/issue/scripts/*.sh \
    content/skills/issue/scripts/testdata/*.sh
  shfmt -i 2 -w content/skills/brainstorming/scripts/*.sh \
    content/skills/brainstorming/scripts/testdata/*.sh
  shfmt -w content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh \
    content/skills/github-tracking/assets/testdata/*.sh
  shfmt -w content/skills/subagent-driven-development/scripts/sdd-workspace \
    content/skills/subagent-driven-development/scripts/task-brief \
    content/skills/subagent-driven-development/scripts/review-package \
    content/skills/subagent-driven-development/scripts/testdata/*.sh
  shfmt -i 2 -w agents/claude/shared/statusline.sh \
    content/skills/systematic-debugging/find-polluter.sh
  shfmt -w content/skills/preflight/scripts/detect-host-architecture \
    content/skills/preflight/scripts/resolve-architecture-context \
    content/skills/preflight/scripts/testdata/*.sh

test:
  ./install-test.sh
  ./install-tools-test.sh
  ./content/skills/issue/scripts/testdata/create-verified-issue-test.sh
  ./content/skills/brainstorming/scripts/testdata/start-server-test.sh
  ./content/skills/brainstorming/scripts/testdata/stop-server-test.sh
  ./content/skills/subagent-driven-development/scripts/testdata/sdd-workspace-test.sh
  ./content/skills/preflight/scripts/testdata/architecture-awareness-test.sh
  ./content/skills/github-tracking/assets/testdata/tracker-test.sh
  {{test_public_safety_command}}
  ./scripts/check-deployed-references-test.sh
  ./scripts/check-workflow-scope-contract-test.sh
  ./scripts/check-cleared-dependencies-test.sh
  ./scripts/check-skill-layout-test.sh
  ./scripts/check-suite-coverage-test.sh
  ./scripts/git-fixture-isolation-test.sh
  ./scripts/select-verification-test.sh
  ./scripts/check-change-aware-policy-test.sh

test-public-safety:
  {{test_public_safety_command}}

skills-check:
  ./scripts/check-skill-layout.sh

suites-check:
  ./scripts/check-suite-coverage.sh

public-safety:
  ./scripts/check-public-safety.sh

commit-check:
  ./scripts/select-verification.sh

references-check:
  ./scripts/check-deployed-references.sh

actions-check:
  actionlint
  zizmor --offline .github/workflows/

verify: tools-check records lint format-check skills-check suites-check test \
        public-safety references-check actions-check

ci: verify
  prek run --all-files
