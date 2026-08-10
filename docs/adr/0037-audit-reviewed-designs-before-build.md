# 0037 — Audit reviewed designs before implementation

## Status

Accepted (2026-08-09)

## Context

`work-issue` freezes external scope and independently reviews each design artifact, but it
does not compare the ADR, specification, and plan together before implementation. A design
can therefore remain locally defensible while its aggregate surface becomes disproportionate,
absorbs another issue, or depends on an exclusion. Discovering that during branch review is
too late because implementation cost is already sunk.

The repository already separates finding validity from finding ownership through scope
charters and debt records. The missing decision is where proportionality is checked and how
that result constrains later review without creating another policy engine.

## Decision

Add a reusable, prose-only `scope-audit` skill. For every non-trivial `work-issue` run, a
fresh independent agent reads the complete frozen charter, the reviewed ADR/specification,
the reviewed plan, and linked ownership as one proposed change after design review and before
TDD. It writes a human-readable report outside the repository and returns `approve` or
`needs-attention`.

The report maps promises to external provenance and components to criteria, compares the
smallest viable alternative, classifies findings, and records a compact approved surface of
components, contracts, complexity, exclusions, and owned deferrals. It is evidence, not
authority. Material expansion returns to `SCOPE CHECKPOINT`; independent adjacent concerns
use the existing debt and tracker workflow; depended-on or worsened concerns cannot be
deferred. Branch review compares the diff with the approved surface.

The workflow uses prompt-contract tests and the existing installed-projection test. It adds
no formal result schema, parser, artifact identity graph, content hashing, transaction
protocol, or live-model evaluation subsystem. A visible change to a reviewed design artifact
invalidates the report and requires another audit.

## Consequences

- Aggregate scope is challenged before implementation cost is sunk.
- The audit adds one independent model pass to ordinary non-trivial issue work.
- Its Markdown report is durable workflow evidence but is not committed product documentation.
- Reviewers and operators, rather than a new parser, judge the report's substantive quality.
- Deterministic tests prove the load-bearing prompt contract, not live-model judgment quality.

## Considered & rejected

- **Embed the check in `work-issue`.** Rejected because the audit would neither be reusable nor
  independent from the workflow assembling the design.
- **Build a formal schema and validator.** Rejected because referential identifiers, parsing,
  artifact hashes, and consistency machinery are disproportionate to a prose workflow.
- **Rely on post-build branch review.** Rejected because it discovers aggregate scope failure
  only after implementation cost is sunk.
