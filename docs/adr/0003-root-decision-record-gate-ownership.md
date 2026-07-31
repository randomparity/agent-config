# 0003 — Root owns decision-record enforcement

## Status

Accepted (2026-07-31)

## Context

This repository publishes configuration for several agents. Claude and Codex each
carry a deployable `decision-records` skill with the same checker, regression suite,
migrator, and record profiles, but neither projection is an appropriate authority for
repository-level records. The root `just verify` recipe currently checks neither
`docs/adr/` nor `docs/debt/`.

The repository also needs one record convention. Existing ADRs predate the current
format, CI already delegates to the root verification recipe, and GitHub branch
protection is external state that repository files cannot require by themselves.

## Decision

Root architecture decisions live at `docs/adr/NNNN-slug.md`; deferred-review work
lives at `docs/debt/NNNN-slug.md`. Each directory has its own monotonically increasing,
four-digit number sequence. The sorted directory listing is the index, so no
hand-maintained table is added.

Every ADR contains `Status`, `Context`, `Decision`, `Consequences`, and
`Considered & rejected`. Every debt record contains `Status`, `Concern`,
`Why deferred`, `Non-regression boundary`, `What would resolve it`, and `Provenance`.
Merged substantive sections are append-only. A later ADR supersedes an earlier one by
adding a dated `Superseded by` banner to the old record's status; completed debt is
retired with a dated `Resolved by` banner. Records are never deleted.

The repository-owned gate package lives under `.github/scripts/`: one checker, its
regression suite, the marker-only migrator, both record profiles, and the workflow
fixture the suite requires. `just verify` runs the suite, checks both root record
profiles, and confirms that the shared executable/profile assets in the Claude and
Codex skill projections match the root package. Root is authoritative; the projection
copies are deployable outputs kept in source because the installer copies native skill
trees directly. Agent-specific workflow templates remain native adapters and are not
canonical gate logic.

CI supplies the pull-request or push base commit and invokes `just ci`, which delegates
to `just verify`; it does not restate record-gate commands. The existing verification
workflow remains the single CI entry point.

Legacy records migrate with the repository-owned `migrate-records.sh`. Marker-only
changes may normalize headings and field markers, while missing status dates are added
from repository history. The migration commit records the paths it changed. Future
format changes use the same migrator-and-gate allowance rather than bypass flags.

Gate ownership has two layers: this repository owns the files and regression suite;
GitHub branch protection owns whether the CI result is mandatory. Until `Verify` is a
required check, the gate is advisory, and that external configuration remains tracked
as deferred work.

## Consequences

- Contributors use one root command for shell, install, workflow, and record checks.
- A gate change updates the root package and both shared projections together; drift
  fails locally and in CI.
- The full regression suite runs on every verification, trading runtime for confidence
  that the checker did not become a silent pass.
- Existing ADR prose remains immutable; only canonical markers and status dates change
  during adoption.
- Native workflow templates may differ in agent syntax or action pins without making an
  agent projection the repository gate owner.
- Repository enforcement cannot make its own CI check required; the debt record for
  branch protection stays open until the GitHub setting is verified.

## Considered & rejected

- **Make the Codex or Claude skill assets authoritative.** Rejected because choosing a
  deployed projection makes another agent's native tree the owner of root policy.
- **Keep three independent gate copies.** Rejected because fixes can drift while every
  individual copy remains internally green.
- **Generate projection assets during installation and remove them from native trees.**
  Rejected for this change because the installer copies whole native skill directories;
  introducing overlay generation expands the installation contract without removing a
  third representation.
- **Run a separate records workflow.** Rejected because CI already has one repository
  entry point, and a second workflow would duplicate scheduling and setup while weakening
  the promise that local and CI verification are the same command.
- **Keep a root ADR index table.** Rejected because every useful field is derivable from
  the record files and adjacent row edits create avoidable merge conflicts.
