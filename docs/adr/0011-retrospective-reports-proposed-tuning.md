# 0011 — Retrospectives report proposed tuning without applying it

## Status

Accepted (2026-08-01)

## Context

Workflow lifecycle events and review annotations provide process telemetry, but analysis
must not perturb the state it measures or turn advisory evidence into unreviewed policy.
The telemetry may also be incomplete, especially for work predating the conventions.

This record migrates
[predecessor ADR 0005](https://github.com/randomparity/claude-config/blob/main/docs/adr/0005-retro-writes-report-doc-with-proposed-tuning.md).

## Decision

`retro` is read-only against external systems and repository history. Its only durable
output is a local, selector-scoped report under `docs/retro/`; it does not commit the
report. Missing source data is reported as unknown rather than treated as zero.

The report may propose concrete tuning, but the skill never applies it. A human reviews
the in-session summary and deliberately routes accepted proposals into the normal issue or
branch workflow.

The policy is tracker-neutral: observe lifecycle evidence without mutation, preserve data
gaps, emit an advisory artifact, and require a separate human-owned tuning action. The
GitHub adapter reads issues, pull requests, label timelines, and `WORK:*` annotations via
read-only `gh` forms. GitHub labels, timeline endpoints, annotations, and CLI mechanics are
adapter details rather than requirements on another tracker.

## Consequences

- Retrospective analysis cannot corrupt the lifecycle evidence used by a later run.
- Reports are durable when a human chooses to commit them, but do not accumulate
  automatically.
- The learn-to-tune loop remains intentionally human-gated.
- Incomplete telemetry remains visible and cannot silently skew aggregates.

## Considered & rejected

- **Apply tuning automatically.** Advisory analysis is insufficient authority to edit
  shared workflow policy.
- **Create a tuning issue or pull request.** That makes the observer mutate the external
  system and weakens the read-only boundary.
- **Post findings to measured work items.** The analysis would change the corpus it reads.
- **Emit console output only.** Non-interactive runs would have no durable deliverable.
- **Reuse solution records.** Process analysis and verified problem solutions have
  different ownership and readers.
