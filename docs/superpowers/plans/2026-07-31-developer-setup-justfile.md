# Developer Setup Justfile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single developer setup and verification workflow that installs repo tools, enables git hooks, and runs the same guardrails locally and in CI.

**Architecture:** `install-tools.sh` remains the bootstrap tool for a new clone, while `Justfile` becomes the stable command surface for daily development. `.pre-commit-config.yaml` delegates to `just verify`, and GitHub Actions installs tools before running `just ci`.

**Tech Stack:** Bash 3.2-compatible shell scripts, `just`, `prek`, Homebrew, apt, dnf/yum, Go fallback installers for `shfmt` and `actionlint`, cargo/uv/pipx fallback installers for `prek` and `zizmor`, cargo fallback for `just`, GitHub Actions, `actionlint`, `zizmor`.

## Global Constraints

- Branch: `feat/developer-setup-3`; base branch: `main`.
- No Windows support in this issue.
- Do not install Homebrew, Go, Rust, Python, pipx, uv, or external package repositories automatically.
- Required commands are `just`, `jq`, `rg`, `shellcheck`, `shfmt`, `gh`, `prek`, `actionlint`, and `zizmor`.
- Hook config invokes `just verify`; `just verify` must not invoke `prek`.
- CI checkout uses `actions/checkout` tag `v7.0.1` pinned to `3d3c42e5aac5ba805825da76410c181273ba90b1`, with `persist-credentials: false`.
- Guardrails are `shellcheck install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh`, `shfmt -d install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh`, `./install-test.sh`, `./install-tools-test.sh`, `./scripts/check-public-safety.sh`, `actionlint`, `zizmor .github/workflows/`, `just verify`, and `prek run --all-files`.

---

## File Structure

- `install-tools.sh`: expand tool list, platform detection, package-manager installers, pinned fallbacks, dry-run test hooks, and final verification.
- `install-tools-test.sh`: shell integration tests for detection, dry-run plans, unsupported platforms, and check-mode failures.
- `Justfile`: developer command surface for setup, hooks, verification, formatting, tests, and CI.
- `.pre-commit-config.yaml`: `prek` hook config delegating to `just verify`.
- `.github/workflows/verify.yml`: CI workflow running `./install-tools.sh` and `just ci`.
- `README.md`: bootstrap, setup, and verification docs.
- `AGENTS.md`: repo guardrail instructions using `just verify`.

## Task 1: Failing Tool-Setup Tests

**Files:**
- Create: `install-tools-test.sh`

**Interfaces:**
- Consumes: existing `install-tools.sh`.
- Produces: executable shell test that fails until `install-tools.sh` supports dry-run distro detection and the expanded tool list.

- [ ] **Step 1: Add the test harness**

Create `install-tools-test.sh` with helpers:

```sh
fail() { printf 'install-tools-test: %s\n' "$*" >&2; exit 1; }
assert_contains() { printf '%s\n' "$1" | rg -q --fixed-strings "$2" || fail "expected output to contain: $2"; }
assert_not_contains() { ! printf '%s\n' "$1" | rg -q --fixed-strings "$2" || fail "expected output not to contain: $2"; }
run_plan() {
  AGENT_CONFIG_DRY_RUN=1 \
  AGENT_CONFIG_TEST_UNAME="$1" \
  AGENT_CONFIG_OS_RELEASE_FILE="$2" \
  AGENT_CONFIG_FAKE_MISSING="${3:-just jq rg shellcheck shfmt gh prek actionlint zizmor}" \
  ./install-tools.sh 2>&1
}
```

The test should create temp `os-release` fixtures for Ubuntu, Debian, Fedora,
RHEL, and an unsupported Linux family. For RHEL, create executable fake `dnf`
and `yum` commands in a temp `bin` directory and prepend it to `PATH` for the
specific assertion that needs that command. Assert dry-run output contains
`sudo apt-get update`, `sudo dnf install`, or `sudo yum install` for the matching
family and contains package names for `just`, `ripgrep`, `ShellCheck`, `prek`,
`actionlint`, and `zizmor` as appropriate.

- [ ] **Step 2: Add fallback and check-mode assertions**

In the same file, assert:

```sh
AGENT_CONFIG_DRY_RUN=1 AGENT_CONFIG_SKIP_PACKAGE_MANAGER=1 AGENT_CONFIG_FAKE_MISSING="shfmt actionlint prek zizmor" ./install-tools.sh
```

prints the pinned `go install` commands for `v3.13.1` and `v1.7.12`, plus
pinned fallback commands for `prek` and `zizmor`, when package-manager
installation is explicitly skipped, and:

```sh
AGENT_CONFIG_FAKE_MISSING="just" ./install-tools.sh --check
```

fails with `missing required tools`.

- [ ] **Step 3: Run the red test**

Run:

```sh
chmod +x install-tools-test.sh
./install-tools-test.sh
```

Expected: fail because `install-tools.sh` does not yet expose the test overrides
or install the expanded tool list.

## Task 2: Tool Installer Implementation

**Files:**
- Modify: `install-tools.sh`
- Modify: `install-tools-test.sh`

**Interfaces:**
- Consumes: test-only env vars from the spec.
- Produces: `./install-tools.sh`, `./install-tools.sh --install`, and `./install-tools.sh --check`.

- [ ] **Step 1: Expand the required tool list**

Replace the fixed command loop with a function that emits:

```text
just
jq
rg
shellcheck
shfmt
gh
prek
actionlint
zizmor
```

Use Bash arrays only in ways compatible with macOS Bash 3.2; do not use
associative arrays.

- [ ] **Step 2: Add platform and distro-family detection**

Add functions equivalent to:

```sh
host_uname() { printf '%s\n' "${AGENT_CONFIG_TEST_UNAME:-$(uname -s)}"; }
os_release_file() { printf '%s\n' "${AGENT_CONFIG_OS_RELEASE_FILE:-/etc/os-release}"; }
normalize_os_value() {
  printf '%s\n' "$1" | tr -d '"' | tr '[:upper:]' '[:lower:]'
}
linux_family() {
  local file id id_like values

  file="$(os_release_file)"
  [[ -f "$file" ]] || return 1
  id="$(awk -F= '$1 == "ID" {print $2}' "$file")"
  id_like="$(awk -F= '$1 == "ID_LIKE" {print $2}' "$file")"
  values="$(normalize_os_value "$id $id_like")"

  case " $values " in
  *" ubuntu "* | *" debian "*) printf 'debian\n' ;;
  *" fedora "*) printf 'fedora\n' ;;
  *" rhel "* | *" centos "* | *" rocky "* | *" almalinux "* | *" ol "*)
    printf 'rhel\n'
    ;;
  *) return 1 ;;
  esac
}
```

`linux_family` parses `ID` and `ID_LIKE`, strips quotes, lowercases values, and
returns `debian`, `fedora`, `rhel`, or a non-zero status for unsupported Linux.
RHEL matches `rhel`, `centos`, `rocky`, `almalinux`, and `ol`.

- [ ] **Step 3: Add package-manager installers**

Implement package maps for Homebrew, apt, dnf, and yum. Dry-run mode prints the
exact command prefixed by `install-tools: would run:`. Real install mode runs:

```sh
brew install <packages>
sudo apt-get update
sudo apt-get install -y <packages>
sudo dnf install -y <packages>
sudo yum install -y <packages>
```

Use `sudo` only when `id -u` is not zero, and fail with an actionable message if
`sudo` is required but absent.

- [ ] **Step 4: Add pinned fallbacks**

Add fallbacks only for tools still missing after package-manager installation:

```sh
go install mvdan.cc/sh/v3/cmd/shfmt@v3.13.1
go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12
cargo install --locked just --version 1.57.0
cargo install --locked prek --version 0.4.11
uv tool install prek==0.4.11
pipx install prek==0.4.11
cargo install --locked zizmor --version 1.28.0
uv tool install zizmor==1.28.0
pipx install zizmor==1.28.0
```

Fail clearly when no supported fallback runtime is available.

- [ ] **Step 5: Run tests and commit**

Run:

```sh
./install-tools-test.sh
shellcheck install-tools.sh install-tools-test.sh
shfmt -d install-tools.sh install-tools-test.sh
```

Commit:

```sh
git add install-tools.sh install-tools-test.sh
git commit -m "feat: support cross-platform tool setup"
```

## Task 3: Justfile, Hooks, and CI

**Files:**
- Create: `Justfile`
- Create: `.pre-commit-config.yaml`
- Create: `.github/workflows/verify.yml`

**Interfaces:**
- Consumes: working `install-tools.sh`.
- Produces: `just setup`, `just verify`, and `just ci`.

- [ ] **Step 1: Add Justfile recipes**

Create recipes:

```make
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

setup:
  ./install-tools.sh
  prek install

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

public-safety:
  ./scripts/check-public-safety.sh

actions-check:
  actionlint
  zizmor .github/workflows/

verify: tools-check lint format-check test public-safety actions-check

ci: verify
  prek run --all-files
```

- [ ] **Step 2: Add prek hook config**

Create `.pre-commit-config.yaml` with a single local hook:

```yaml
repos:
  - repo: local
    hooks:
      - id: verify
        name: just verify
        entry: just verify
        language: system
        pass_filenames: false
```

- [ ] **Step 3: Add GitHub Actions workflow**

Create `.github/workflows/verify.yml` with read-only permissions, pinned
checkout, setup, and CI:

```yaml
name: Verify

on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Install tools
        run: ./install-tools.sh
      - name: Verify
        run: just ci
```

- [ ] **Step 4: Run checks and commit**

Run:

```sh
just verify
prek run --all-files
```

Commit:

```sh
git add Justfile .pre-commit-config.yaml .github/workflows/verify.yml
git commit -m "ci: add shared setup guardrails"
```

## Task 4: Documentation and Repo Instructions

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: `Justfile`, hook config, and CI workflow.
- Produces: contributor-facing setup and verification docs.

- [ ] **Step 1: Update README setup docs**

Replace the raw install-tool flow with:

```sh
./install-tools.sh
just setup
```

Document `./install-tools.sh --check`, `just verify`, `just format`, and that
Linux setup supports Ubuntu/Debian/Fedora/RHEL families through `/etc/os-release`.

- [ ] **Step 2: Update AGENTS guardrails**

Replace the raw guardrail block with:

```sh
just verify
```

Mention that `just setup` installs tools and enables hooks for local
development.

- [ ] **Step 3: Run docs checks and commit**

Run:

```sh
just verify
```

Commit:

```sh
git add README.md AGENTS.md
git commit -m "docs: document developer setup"
```

## Task 5: Final Verification and Review Prep

**Files:**
- Modify: plan checkboxes only if tasks are tracked in the committed plan.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: branch ready for review and shipping.

- [ ] **Step 1: Re-read the branch diff**

Run:

```sh
git diff --stat main...HEAD
git diff main...HEAD
```

Check for duplicated guardrail strings outside `Justfile`, unpinned CI actions,
unchecked shell inputs, and docs that mention commands not implemented.

- [ ] **Step 2: Run full local verification**

Run:

```sh
just verify
prek run --all-files
```

- [ ] **Step 3: Prepare review summary**

Record that the security-relevant surfaces are package-manager command
execution, pinned dependency fallbacks, git hook execution, and CI workflow
permissions. These surfaces trigger the later threat scan.
