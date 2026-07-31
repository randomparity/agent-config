# Developer Setup Justfile Design

Issue: #3

ADR: [0002. Developer Setup Entrypoint and Hooks](../../adr/0002-developer-setup-entrypoint-and-hooks.md)

Branch: `feat/developer-setup-3`
Base branch: `main`

## Context

This repo now has a public installer, install tests, and a public-safety scan,
but a new contributor still has to discover and run raw commands manually. The
current `install-tools.sh` checks only `jq`, `rg`, `shellcheck`, `shfmt`, and
`gh`, installs through Homebrew on macOS, and falls back to Go only for `shfmt`.

Issue #3 asks for a single developer setup entry point that installs repo
dependencies and sets up git/CI commit hooks for macOS and Linux users on
Ubuntu/Debian/Fedora/RHEL-family systems.

## Goals

- Add `just setup` as the normal local bootstrap for developers who already
  have `just`.
- Keep `./install-tools.sh` as the first-run bootstrap for users who do not
  have `just` yet.
- Install and check repository tools: `just`, `jq`, `rg`, `shellcheck`,
  `shfmt`, `gh`, `prek`, `actionlint`, and `zizmor`.
- Detect macOS through `uname` and Linux distro families through
  `/etc/os-release`.
- Support Homebrew, apt, dnf, and yum package managers.
- Configure local git hooks with `prek install`.
- Make hooks and CI invoke the same core guardrail recipe, `just verify`.
- Update README and AGENTS so future contributors use the durable setup and
  verification commands.

## Non-Goals

- No Windows support in this issue.
- No automatic installation of Homebrew, Go, Rust, Python, pipx, uv, or package
  repository signing keys.
- No host-specific or private setup state committed to this public repo.
- No replacement of the existing agent installer behavior.

## Architecture

`install-tools.sh` is responsible for tool detection and installation. It must
support these modes:

```sh
./install-tools.sh
./install-tools.sh --install
./install-tools.sh --check
```

The install mode detects missing commands, installs what it can through the
host package manager, then uses pinned fallbacks only for tools not available
after the package-manager attempt. Check mode is read-only and reports missing
tools.

The current stable versions verified on 2026-07-31 are:

| Tool | Source | Version |
|---|---|---|
| just | `casey/just` GitHub release | 1.57.0 |
| shfmt | `mvdan/sh` GitHub release | v3.13.1 |
| actionlint | `rhysd/actionlint` GitHub release | v1.7.12 |
| prek | `j178/prek` GitHub release / PyPI | v0.4.11 / 0.4.11 |
| zizmor | `zizmorcore/zizmor` GitHub release / PyPI | v1.28.0 / 1.28.0 |
| actions/checkout | GitHub release | v7.0.1 |

`install-tools.sh` should use these package names:

| Command | Homebrew | apt | dnf/yum |
|---|---|---|---|
| `just` | `just` | `just` | `just` |
| `jq` | `jq` | `jq` | `jq` |
| `rg` | `ripgrep` | `ripgrep` | `ripgrep` |
| `shellcheck` | `shellcheck` | `shellcheck` | `ShellCheck` |
| `shfmt` | `shfmt` | `shfmt` | `shfmt` |
| `gh` | `gh` | `gh` | `gh` |
| `prek` | `prek` | `prek` | `prek` |
| `actionlint` | `actionlint` | `actionlint` | `actionlint` |
| `zizmor` | `zizmor` | `zizmor` | `zizmor` |

Package-manager repositories differ, so install mode must still verify the
final command list after attempting package installs. Fallbacks are:

- `shfmt`: `go install mvdan.cc/sh/v3/cmd/shfmt@v3.13.1`
- `actionlint`: `go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12`
- `just`: `cargo install --locked just --version 1.57.0`
- `prek`: prefer `cargo install --locked prek --version 0.4.11`; otherwise
  `uv tool install prek==0.4.11`; otherwise `pipx install prek==0.4.11`
- `zizmor`: prefer `cargo install --locked zizmor --version 1.28.0`;
  otherwise `uv tool install zizmor==1.28.0`; otherwise
  `pipx install zizmor==1.28.0`

If no supported package manager or fallback runtime is available, the script
must fail with the missing command and a suggested installation path. It must
not claim success until `--check` passes. After fallback installers run, the
script refreshes its current `PATH` with common install directories such as
`$HOME/.cargo/bin`, `$HOME/.local/bin`, and the Go bin directory. In GitHub
Actions, it also appends discovered fallback directories to `$GITHUB_PATH` so
later workflow steps can see tools installed by the setup step.

## Just Recipes

Add `Justfile` recipes:

```text
setup
verify
tools-check
lint
format-check
format
test
public-safety
hooks
ci
```

`setup` runs `./install-tools.sh` and then `prek install`. `verify` runs
`tools-check`, `lint`, `format-check`, `test`, `public-safety`, and
`actionlint`/`zizmor` when workflows are present. `ci` runs `verify` and
`prek run --all-files` so CI proves both the guardrail recipe and hook config.

## Hook and CI Configuration

`.pre-commit-config.yaml` uses one local hook:

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

The GitHub Actions workflow runs on pushes to `main` and pull requests. It
checks out with `actions/checkout` pinned to commit
`3d3c42e5aac5ba805825da76410c181273ba90b1` for tag `v7.0.1`, installs tools
with `./install-tools.sh`, and runs `just ci`.

The workflow permissions are `contents: read`, and checkout must set
`persist-credentials: false`.

## Testing

Add `install-tools-test.sh` to exercise platform detection without invoking
host package managers. `install-tools.sh` should expose test-only environment
overrides:

- `AGENT_CONFIG_TEST_UNAME` overrides `uname -s`.
- `AGENT_CONFIG_OS_RELEASE_FILE` overrides `/etc/os-release`.
- `AGENT_CONFIG_FAKE_MISSING` treats listed commands as missing.
- `AGENT_CONFIG_DRY_RUN=1` prints package-manager and fallback commands instead
  of executing them.
- `AGENT_CONFIG_SKIP_PACKAGE_MANAGER=1` skips package-manager installation so
  fallback paths can be tested deterministically.

The test covers:

- macOS selects Homebrew packages.
- Ubuntu and Debian select apt.
- Fedora selects dnf.
- RHEL-family systems select dnf when present and yum otherwise.
- Unknown Linux families fail with an unsupported-family message.
- `--check` reports missing tools.
- Dry-run fallback output includes pinned fallback versions when package-manager
  installation is explicitly skipped.

## Threat Model

### Boundary Inventory

- New package-manager boundary: local setup may run Homebrew, apt, dnf, or yum.
- New language-fallback boundary: local setup may run Go, cargo, uv, or pipx
  when they are already installed.
- New hook boundary: `git commit` can invoke `just verify` through `prek`.
- New CI boundary: GitHub Actions runs repository scripts on pull requests.
- Existing public-git boundary: generated setup files must remain free of
  host-specific paths and secrets.

### Actors

- Local operator running setup on a trusted development host.
- Contributor opening a pull request.
- GitHub-hosted CI runner executing workflow steps.
- Repository maintainer reviewing tooling changes.

### Controls

- Package-manager boundary: commands are selected from a fixed package map, not
  from untrusted input; privileged package managers require the operator's
  local sudo policy.
- Language-fallback boundary: fallbacks use verified pinned versions and run
  only when the runtime already exists.
- Hook boundary: the hook invokes `just verify`; `verify` must not invoke
  `prek` to avoid recursion.
- CI boundary: workflow permissions are read-only, checkout is pinned by full
  commit SHA, and credentials are not persisted.
- Public-git boundary: `just verify` includes `scripts/check-public-safety.sh`.

### Out Of Scope

- A malicious local package manager, Homebrew tap, Python index, Go proxy, or
  Rust registry can still serve compromised packages.
- A contributor can still modify CI or setup scripts in a PR; review,
  actionlint, zizmor, and pinned actions reduce but do not remove this risk.
- Unsupported Linux distributions must install tools manually or add a future
  tested package-family adapter.

## Verification

Guardrail commands for this issue:

```sh
shellcheck install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
shfmt -d install.sh install-tools.sh install-test.sh install-tools-test.sh scripts/*.sh
./install-test.sh
./install-tools-test.sh
./scripts/check-public-safety.sh
actionlint
zizmor --offline .github/workflows/
just verify
prek run --all-files
```
