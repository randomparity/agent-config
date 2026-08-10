set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  just --list

setup:
  AGENT_CONFIG_SETUP_HOOKS=1 ./install-tools.sh

hooks:
  #!/usr/bin/env bash
  set -euo pipefail
  marker='# agent-config: managed pre-push hook'
  hook_dir="$(git rev-parse --git-path hooks)"
  destination="$hook_dir/pre-push"
  source='scripts/pre-push-hook'
  prek install
  mkdir -p "$hook_dir"
  if [[ -L $destination || ( -e $destination && ! -f $destination ) ]]; then
    echo "hooks: refusing unsafe pre-push destination: $destination" >&2
    exit 1
  fi
  if [[ -f $destination ]] && ! rg -qxF "$marker" "$destination"; then
    echo "hooks: refusing foreign pre-push hook: $destination" >&2
    exit 1
  fi
  temporary="$(mktemp "$hook_dir/.pre-push.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT
  cp "$source" "$temporary"
  chmod +x "$temporary"
  mv -f "$temporary" "$destination"
  trap - EXIT

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

# Shell sources are discovered from Git, never enumerated: a tracked file is a
# shell source when its name ends in .sh or its first line is a Bash shebang,
# which also covers the extensionless helpers (scripts/list-shell-sources.sh).
# A new script or suite is linted, formatted and run with no recipe edit, and a
# `testdata/` suite is discovered the same way — it stays excluded only from
# the installed payload, never from the gates (ADR 0025).
lint:
  #!/usr/bin/env bash
  set -euo pipefail
  files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(./scripts/list-shell-sources.sh --all -z)
  shellcheck "${files[@]}"

# The two-space subset is the vendored brainstorming tree (ADR 0005's
# re-vendor argument: an upstream update reviews the upstream diff, so a
# reformat here would cost that diff for nothing), the two-space record gate
# under .github/scripts and its byte-identical decision-records asset twins,
# and two first-party sources that predate the gate at two-space indent.
# list-shell-sources.sh owns the classification.
format-check:
  #!/usr/bin/env bash
  set -euo pipefail
  tabs=()
  while IFS= read -r -d '' file; do
    tabs+=("$file")
  done < <(./scripts/list-shell-sources.sh --tabs -z)
  two_space=()
  while IFS= read -r -d '' file; do
    two_space+=("$file")
  done < <(./scripts/list-shell-sources.sh --two-space -z)
  shfmt -d "${tabs[@]}"
  shfmt -i 2 -d "${two_space[@]}"

format:
  #!/usr/bin/env bash
  set -euo pipefail
  tabs=()
  while IFS= read -r -d '' file; do
    tabs+=("$file")
  done < <(./scripts/list-shell-sources.sh --tabs -z)
  two_space=()
  while IFS= read -r -d '' file; do
    two_space+=("$file")
  done < <(./scripts/list-shell-sources.sh --two-space -z)
  shfmt -w "${tabs[@]}"
  shfmt -i 2 -w "${two_space[@]}"

test:
  #!/usr/bin/env bash
  set -euo pipefail
  # Every tracked suite runs here except the records gate's own suite, which
  # `just records` already executes; running it here too would duplicate the
  # repository's largest suite for no new evidence.
  count=0
  while IFS= read -r -d '' suite; do
    case $suite in
    .github/scripts/check-records-test.sh | \
      content/skills/decision-records/assets/check-records-test.sh)
      continue
      ;;
    esac
    printf '== %s\n' "$suite"
    "./$suite"
    count=$((count + 1))
  done < <(git ls-files -z -- '*-test.sh')
  if ((count == 0)); then
    printf 'test: no suites discovered\n' >&2
    exit 1
  fi
  printf 'test: %s suites passed\n' "$count"

skills-check:
  ./scripts/check-skill-layout.sh

carrier-check:
  ./scripts/check-carrier-drift.sh

shared-standards-check:
  ./scripts/check-shared-standards.sh

public-safety:
  ./scripts/check-public-safety.sh

# The one recipe the pre-commit hook invokes (ADR 0039). verify depends on it
# too, so a static gate added to either chain reaches both and the hook never
# names recipes of its own.
commit-check: lint format-check public-safety

push-check:
  ./scripts/verify-push.sh

references-check:
  ./scripts/check-deployed-references.sh

actions-check:
  actionlint
  zizmor --offline .github/workflows/

verify: tools-check records commit-check skills-check carrier-check \
        shared-standards-check test references-check actions-check
  prek run --all-files --stage pre-commit --dry-run

ci:
  #!/usr/bin/env bash
  set -euo pipefail
  started=$SECONDS
  echo 'verification selection: full ci'
  just verify
  echo "verification total elapsed seconds: $((SECONDS - started))"
