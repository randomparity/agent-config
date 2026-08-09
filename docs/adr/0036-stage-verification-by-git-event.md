# 0036 — Stage verification by Git event

## Status

Accepted (2026-08-09)

## Context

ADR 0002 made `just verify` the one guardrail command used by local hooks and CI. That
centralized the contract, but it also makes every commit run every repository suite. CI then
runs the same full suite a second time through `prek run --all-files`. Small changes pay for
unrelated installation, record, workflow, and Git-fixture suites without adding useful
commit-time evidence.

Issue #93 requires cheap, focused commit checks without an inordinate loss of coverage. The
operator additionally requires branch pushes to be thorough and to use the same command as
GitHub CI. Global recipes, shared contracts, hook configuration, and unclassified paths must
continue to fail closed to full verification.

ADR 0002 remains authoritative for tool bootstrap, platform detection, package-manager
precedence, pinned fallbacks, and actionable setup failures. This record replaces only its
verification topology: the decision that every local hook and CI invocation uses the same
complete guardrail command.

## Decision

Keep `just verify` as the complete repository suite, but refine ADR 0002 by selecting the
command according to the Git event.

- The pre-commit hook passes staged paths to a repository-owned selector. The selector maps
  known, isolated surfaces to focused Just recipes, reports the selected recipes and their
  elapsed time, and invokes only fixed recipe names. An empty change does no work. Any global,
  shared-contract, hook-configuration, mixed-risk, or unknown path selects `just ci` instead.
- The pre-push hook invokes `just ci` with no path filtering. GitHub Actions invokes the same
  `just ci` recipe. That recipe times one invocation of `just verify`; it never recursively
  executes the pre-commit hook.
- `just setup` installs both pre-commit and pre-push shims through the repository `hooks`
  recipe. Full verification validates that both configured stages parse without executing
  either hook.
- Focused recipe mapping is tested as policy. Timing values are evidence in output, never
  pass/fail thresholds.

## Consequences

- Ordinary commits receive faster feedback proportional to the changed surface.
- A commit is not the final coverage boundary. Every normal branch push and every GitHub CI
  leg still runs the complete suite through the same recipe.
- Contributors who bypass or lack the pre-push hook still encounter the complete suite in CI.
- New or moved paths initially cost a full verification until the tested selector policy is
  deliberately extended.
- The selector and its path map become part of the repository verification contract and must
  run in the repository's supported local-hook environments.

## Considered & rejected

- **Declare many path-filtered hooks in the prek configuration.** Rejected because selection,
  ordering, timing, and fallback policy would be spread across hook entries instead of one
  testable repository component.
- **Keep full verification on commits and optimize suites internally.** Rejected because even
  perfectly parallel suites still perform unrelated work and cannot make a small commit cheap.
- **Use focused checks for pushes as well as commits.** Rejected because a path map is a useful
  feedback optimization, not sufficient proof for integration, portability, or shared-contract
  behavior.
- **Cache successful suites across commits.** Rejected because cache invalidation would add a
  second correctness contract and would not guarantee that pushes and CI execute identical
  commands.
