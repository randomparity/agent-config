# 0039 — Commit hooks run the static gates

## Status

Accepted (2026-08-09)

## Context

ADR 0036 staged verification by Git event: a commit-time selector
(`scripts/select-verification.sh`) mapped staged paths to focused recipes, reported
unclassified paths as deferred, and left branch push and CI running the complete
`just ci`. The motivation — a commit should not pay for the full suite — was real, and
remains real.

The selector's coverage never justified its machinery. Its path map classified five
patterns (ADR records, debt records, other docs, and the two public-safety files) and
deferred everything else, so most commits ran a near-empty selection and the full suite
arrived at push time regardless. The map, the fallback policy, and the 356-line suite
around them tested the selection machinery itself: near-miss paths, rename endpoints,
deletions, dirty worktrees — behavior of a component whose only job was to save seconds.
A classified-but-wrong mapping is also a silent hole: a path matched to too-small a
recipe set looks covered and is not.

## Decision

The pre-commit hook runs the fast static gates directly:

```sh
just lint format-check public-safety
```

These are path-independent, complete for their class, and take seconds. The selector, its
suite, and the `commit-check` recipe are deleted; the prek hook entry names the three
recipes itself. This record supersedes ADR 0036.

The proof boundary is unchanged: the pre-push hook still validates ref updates and runs
`just ci` in an isolated disposable worktree (`scripts/verify-push.sh`), and GitHub CI
runs the same `just ci`. Nothing about push or CI verification is selected, deferred, or
reduced.

## Consequences

- Commit-time feedback is a fixed, auditable command. There is no mapping to extend when
  a new surface appears and no way for a path to be classified into too little checking.
- A commit that touches only prose now pays for shellcheck and shfmt over the whole tree
  (seconds) instead of a records-only subset. Bounded, and it catches what the selector
  never could: a prose commit whose branch also carries uncommitted-adjacent shell
  breakage.
- Everything the selector deferred still reaches the full suite at push and CI, which
  ADR 0036 already established as the proof boundary; contributors who bypass the local
  hooks still meet the complete suite in CI.

## Considered & rejected

- **Extend the selector's path map to cover more surfaces.** Rejected: the map is the
  cost. Every entry is a claim about which recipes a path needs, maintained forever, and
  tested by fixtures that exist only to exercise the map.
- **Run full `just verify` on every commit.** Rejected: ADR 0036's motivation stands —
  the suite includes installation fixtures and a worktree-isolated push rehearsal that a
  docs commit should not wait for.
- **Keep the selector only for the records paths.** Rejected: two mechanisms for one job;
  the records gate runs at push for the docs-only commits that skip it locally, which is
  the same boundary the selector deferred to anyway.
