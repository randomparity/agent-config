# 0002. Developer Setup Entrypoint and Hooks

## Status

Accepted

## Context

This public repo needs a repeatable path for contributors to install local
tooling, enable commit hooks, and run the same guardrails that CI runs. The
current bootstrap script checks a small tool list and installs through Homebrew
or a narrow Go fallback only. It does not model Linux distro families, git hook
installation, or GitHub Actions verification.

Tooling setup crosses a trust boundary because it may run package managers,
`sudo`, or language package installers on a developer machine or CI runner.
The repo also needs one maintainable guardrail recipe so local hooks, CI, and
documentation do not drift.

## Decision

Make `just` the repository command entry point. `just setup` installs required
tools and runs `prek install`; `just verify` is the core guardrail recipe used
by local hooks and CI.

`install-tools.sh` remains the bootstrap installer because a new clone may not
have `just` yet. It detects macOS through `uname` and Linux families through
`/etc/os-release`, supporting Homebrew, apt, dnf, and yum. Package-manager
installs are primary. Pinned language-runtime fallbacks are allowed only when
the required runtime already exists, and setup must fail with an actionable
message rather than installing a new language runtime implicitly.

Use `prek` for local hooks. The hook config invokes `just verify` instead of
retyping individual guardrail commands. GitHub Actions installs tools with
`install-tools.sh`, then runs `just verify` and `prek run --all-files` to prove
both the recipe and the hook configuration work.

## Consequences

- New contributors can start with `./install-tools.sh` or `just setup`.
- Local hooks and CI share a single guardrail command surface.
- Linux support is explicit for Ubuntu/Debian, Fedora, and RHEL-family systems.
- CI workflow changes add `actionlint` and `zizmor` to the repository tool set.
- Unsupported systems or missing fallback runtimes fail early with exact next
  steps instead of silently skipping tools.

## Considered & Rejected

- Keep raw shell commands in README and hooks. Rejected because duplicated
  guardrail text drifts across docs, hooks, and CI.
- Use native git hook files without `prek`. Rejected because this repo's global
  workflow expects `prek install`, and `prek` can run the same hook config in CI.
- Install Rust, Go, Python, or package-manager repositories automatically.
  Rejected because bootstrapping language runtimes or external package feeds is
  too invasive for a public setup script; the script may use them only when the
  operator already has them.
- Use pre-built binary curl installers by default. Rejected because piping
  installer scripts or downloaded binaries into local setup broadens the supply
  chain more than package-manager installs and pinned runtime fallbacks.
