set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  just --list

setup:
  AGENT_CONFIG_SETUP_HOOKS=1 ./install-tools.sh

hooks:
  prek install

tools-check:
  ./install-tools.sh --check

lint:
  shellcheck install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh

format-check:
  shfmt -d install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh

format:
  shfmt -w install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh

test:
  ./install-test.sh
  ./install-tools-test.sh
  ./scripts/install-identity-test.sh

public-safety:
  ./scripts/check-public-safety.sh

actions-check:
  actionlint
  zizmor --offline .github/workflows/

verify: tools-check lint format-check test public-safety actions-check

ci: verify
  prek run --all-files
