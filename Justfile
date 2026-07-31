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
  for agent in claude codex; do
    for asset in $shared_assets; do
      root_asset=".github/scripts/$asset"
      deployed_asset="agents/$agent/shared/skills/decision-records/assets/$asset"
      if ! cmp -s "$root_asset" "$deployed_asset"; then
        echo "record gate mismatch: $deployed_asset differs from $root_asset" >&2
        exit 1
      fi
    done
  done

lint:
  shellcheck install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh \
    .github/scripts/*.sh .github/scripts/profiles/*.sh

format-check:
  shfmt -d install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
  shfmt -i 2 -d .github/scripts/*.sh .github/scripts/profiles/*.sh

format:
  shfmt -w install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
  shfmt -i 2 -w .github/scripts/*.sh .github/scripts/profiles/*.sh

test:
  ./install-test.sh
  ./install-tools-test.sh
  ./scripts/check-public-safety-test.sh

public-safety:
  ./scripts/check-public-safety.sh

actions-check:
  actionlint
  zizmor --offline .github/workflows/

verify: tools-check records lint format-check test public-safety actions-check

ci: verify
  prek run --all-files
