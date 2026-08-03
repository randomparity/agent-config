set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

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
  shared_assets="$shared_assets profiles/adr.sh profiles/debt.sh"
  for asset in $shared_assets; do
    root_asset=".github/scripts/$asset"
    skill_asset="content/skills/decision-records/assets/$asset"
    if ! cmp -s "$root_asset" "$skill_asset"; then
      echo "record gate mismatch: $skill_asset differs from $root_asset" >&2
      exit 1
    fi
  done

lint:
  shellcheck install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh \
    .github/scripts/*.sh .github/scripts/profiles/*.sh \
    content/skills/issue/scripts/*.sh \
    content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh \
    content/skills/github-tracking/assets/testdata/*.sh

format-check:
  shfmt -d install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
  shfmt -i 2 -d .github/scripts/*.sh .github/scripts/profiles/*.sh
  shfmt -d content/skills/issue/scripts/*.sh
  shfmt -d content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh \
    content/skills/github-tracking/assets/testdata/*.sh

format:
  shfmt -w install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
  shfmt -i 2 -w .github/scripts/*.sh .github/scripts/profiles/*.sh
  shfmt -w content/skills/github-tracking/assets/*.sh \
    content/skills/github-tracking/assets/profiles/*.sh \
    content/skills/github-tracking/assets/testdata/*.sh

test:
  ./install-test.sh
  ./install-tools-test.sh
  ./content/skills/issue/scripts/create-verified-issue-test.sh
  ./content/skills/github-tracking/assets/tracker-test.sh
  ./scripts/check-public-safety-test.sh
  ./scripts/check-deployed-references-test.sh
  ./scripts/check-workflow-scope-contract-test.sh
  ./scripts/check-cleared-dependencies-test.sh

skills-check:
  ./scripts/check-skill-layout.sh

public-safety:
  ./scripts/check-public-safety.sh

references-check:
  ./scripts/check-deployed-references.sh

actions-check:
  actionlint
  zizmor --offline .github/workflows/

verify: tools-check records lint format-check skills-check test public-safety references-check actions-check

ci: verify
  prek run --all-files
