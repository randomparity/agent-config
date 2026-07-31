# Root Decision-Record Enforcement Design

Issue: #7

## Approved requirement and assumptions

Issue #7 requires an accepted record convention, a root-owned mechanical gate,
integration with the repository verification entry point, successful execution of the
repository-owned regression suite, migration of current records, and contributor setup
documentation. This is a dispatched design: the issue body and acceptance criteria are
the approved requirement.

The design preserves the existing decision-record behavior in the Claude and Codex
projections except where it conflicts with the accepted root convention: open debt must
carry `review-by:`. It does not otherwise redesign the checker. Agent-native workflow
templates may retain native invocation prose and action pins, while shared checker
behavior must not drift.

## Goals

- Define numbering, indexing, immutability, supersession, resolution, migration, and
  gate ownership in ADR 0003.
- Validate every root ADR and debt record through `just verify`.
- Make `.github/scripts/` authoritative for the gate engine, suite, migrator, and
  profiles, with the one root-policy correction for required open-debt review dates.
- Fail verification when Claude or Codex deployable gate logic differs from root.
- Keep CI on the same `just ci` to `just verify` path used by contributors.
- Report and resolve or track every finding from the first real root-owned run.

## Non-goals

- Redesigning decision-record parsing or changing rule semantics beyond the required
  open-debt review date.
- Generating native skill trees during installation.
- Making GitHub branch-protection changes from repository code.
- Adding a hand-maintained ADR or debt index.
- Adding dependencies or a migration registry.

## Approaches considered

### Root package with verified native copies — chosen

Copy the current checker package to `.github/scripts/`, run it from the root recipe, and
compare its shared assets byte-for-byte with both native projections. This names a neutral
owner, preserves existing behavior apart from the accepted review-date correction, and
catches drift without changing installation.

### One agent projection owns root enforcement

Running root verification directly from the Codex or Claude skill would avoid a third
copy. It also makes one deployed agent layout the accidental policy owner and leaves a
fresh clone dependent on the internal organization of that projection.

### Generate projections from root

Removing the native copies and overlaying root assets at install time gives stronger
single-source storage. It also changes `install.sh`, installation tests, and the ability
to inspect a complete native skill tree in source. That expansion is not needed to meet
the issue and conflicts with the current canonical-plus-native architecture.

## Architecture

The root package contains:

```text
.github/scripts/
  check-records.sh
  check-records-test.sh
  migrate-records.sh
  records.yml
  profiles/
    adr.sh
    debt.sh
```

`records.yml` is a regression-suite fixture in the publishing layout, not another active
workflow. The active `.github/workflows/verify.yml` runs `just ci` with full git history
and a base commit. `just ci` delegates to `just verify`.

The `records` recipe in `Justfile` performs three checks in order:

1. Run `.github/scripts/check-records-test.sh` from the repository-owned copy.
2. Run `.github/scripts/check-records.sh` with `RECORD_PROFILES="adr debt"` and the
   optional `BASE_SHA` supplied by CI.
3. Compare the root checker, suite, migrator, and two profiles with the corresponding
   Claude and Codex skill assets. A mismatch names both paths and fails.

The workflow templates inside each agent skill are native adapters, so they are excluded
from byte equality. They do not define parsing, migration, or record semantics.

The existing `lint` and `format-check` recipes add the three executable root scripts and
both sourced profiles to their explicit ShellCheck and shfmt paths. The profiles remain
non-executable and shebang-free, but they are shell source and receive the same static
analysis as the engine that loads them.

## Record model

ADRs and debt records use independent four-digit sequences because they answer different
questions. The filenames and directory listing are their index. Root ADRs require the five
sections in ADR 0003. Root debt records require the six sections in ADR 0003 plus bare
`target:` provenance and, while open, a bare ISO-8601 `review-by:` date.

Merged record substance is append-only. Status is the controlled lifecycle surface:
accepted ADRs gain a dated supersession banner. Resolving debt replaces `Open` with a
dated `Resolved by` banner and removes `review-by:` while leaving substantive sections
intact. Files are never removed, moved, replaced by symlinks, or rewritten in place.

The existing ADRs migrate only their canonical markers and status dates. Their original
commit date, 2026-07-31, supplies the missing accepted date. The root migrator must first
demonstrate the marker changes are permitted; manual status-date additions stay confined
to the exempt Status sections.

## Failure behavior

- Missing root assets stop the regression suite before its cases run.
- An unset `RECORD_PROFILES` is fatal; the recipe always sets both profiles.
- Local verification without `BASE_SHA` validates current record shape and reports that
  immutable-history comparison was skipped.
- On pull requests, CI sets `BASE_SHA` from `github.event.pull_request.base.sha`; on
  pushes to `main`, it uses `github.event.before`. Checkout uses `fetch-depth: 0`, making
  either event's commit reachable before `just ci` checks shape plus deletion, rewrite,
  renumbering, and gate self-protection.
- A projection mismatch fails with the root and deployed paths that differ.
- A first-run finding is fixed in this branch when it concerns migrated records or gate
  installation. A finding outside repository control is captured in a debt record and a
  linked tracker issue.

## First-run report

The PR body is the delivery artifact for the first root-owned regression and record-gate
run. It names the exact commands and regression case count, lists every initial finding,
and links each one to its fixing commit or to both its debt record and tracker issue. The
final green run stays separate from this history so remediation cannot erase evidence of
what the adopted gate found.

## Threat model

### Boundary inventory

- A contributor-controlled pull-request tree enters the CI shell checker.
- Record filenames and Markdown contents enter the gate parser.
- Git history and the event-provided base SHA enter immutable-history comparison.
- Root gate assets are copied into agent-native installation payloads through source
  projections.

### Actors and trust

Contributors may be mistaken or hostile; their record contents, filenames, and gate edits
are untrusted. GitHub Actions supplies the event metadata and base commit. Maintainers
control branch-protection policy. Local contributors control their own `BASE_SHA` and can
only affect their local result.

### Controls

- The adopted checker quotes paths, rejects symlinks and malformed base refs, and fails
  degraded paths instead of reporting success over no records.
- CI uses a read-only token, disables checkout credential persistence, and fetches full
  history so the base SHA is reachable.
- The regression suite runs before record validation and tests the checker plus migrator.
- Byte comparison prevents a projection from silently changing deployed gate behavior.
- The updated public-safety, ShellCheck, shfmt, actionlint, and zizmor recipes cover the
  new root paths through `just verify`.

### Out of scope

Repository files cannot force GitHub to require the `Verify` check. Until maintainers set
and verify branch protection, a privileged merge can bypass CI; the adoption records this
as debt rather than implying enforcement that does not exist.

## Documentation

`README.md` describes record creation, next-number selection, supersession/resolution,
migration, and verification. `AGENTS.md` points contributors to that workflow and keeps
`just verify` as the completion gate. Documentation names repository paths and commands,
not predecessor-local ADR numbers.

## Acceptance tests

- A new `records` recipe fails before root assets exist, then passes after installation.
- The root regression suite reports its full successful case count.
- The root checker validates `docs/adr/` and `docs/debt/` with both profiles.
- Mutating one projected checker asset makes `just verify` fail; restoring it passes.
- ShellCheck and shfmt run explicitly against all five authoritative shell assets.
- The root checker passes with `BASE_SHA=HEAD^` as a push-style reachable commit and with
  the feature branch's merge base against `origin/main` as a pull-request-style commit.
- Actionlint and zizmor prove the workflow still invokes only `just ci` for repository
  checks; the two concrete base-ref runs prove the selected history paths are usable.
- The PR body records the first-run command, case count, findings, and resolution links.
- `just verify` passes from the feature branch after legacy-record migration.

## Rollback

Rollback is a forward change, not a literal revert that deletes immutable records. Preserve
ADR 0003, the branch-protection debt record, and every marker/status migration. If root gate
ownership changes, add a superseding ADR and its banner; resolve or carry the debt according
to the replacement's enforcement. Only the executable gate package, active recipe wiring,
projection equality check, workflow environment, and contributor instructions may be removed.
