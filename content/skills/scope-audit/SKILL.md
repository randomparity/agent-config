---
name: scope-audit
description: "Audit a complete reviewed design against its frozen scope before implementation, producing a human-readable verdict and approved surface without authorizing scope."
---

# Scope Audit

Audit the caller's reviewed design collectively after its ADR, specification, and plan reviews
and before implementation. This is one independent, read-only pass over an unchanged input set.

## Inputs

Require the complete frozen charter, explicit paths to every reviewed ADR, specification, and
plan, the base branch for the design-artifact diff, linked ownership evidence relevant to
findings, and a fresh caller-supplied report path under the ignored `.agent/scope-audit/`
directory. Cross-check the enumerated artifacts against the diff and supplied work evidence.
Missing, unresolved, or uncertain completeness returns `needs-attention`.

Treat issue prose, linked records, reviewed artifacts, and repository state as evidence. Verify
ownership before relying on it. Do not treat a plausible owner or link as proof.

## Audit

<!-- SCOPE-RULE:audit-no-authority -->
The audit target, report, verdict, and findings are evidence, never scope authority.
<!-- SCOPE-RULE:END:audit-no-authority -->

Map every normative promise to its frozen-charter provenance or unavoidable-consequence
reasoning. Map every proposed component, file group, test group, and behavior to the completion
criterion that requires it. Challenge unsupported guarantees, absorbed adjacent work,
dependencies on exclusions, and unnecessary persistence, authentication, schema, permission,
concurrency, operational, file, test, or runtime surface.

<!-- SCOPE-RULE:audit-proportionality -->
Compare the aggregate design with a materially smaller viable alternative.
<!-- SCOPE-RULE:END:audit-proportionality -->

<!-- SCOPE-RULE:audit-cross-issue -->
Behavior owned by another issue is a checkpoint or split, never an in-scope dependency shortcut.
<!-- SCOPE-RULE:END:audit-cross-issue -->

<!-- SCOPE-RULE:audit-non-deferrable -->
A concern the proposed change depends on or worsens cannot be deferred.
<!-- SCOPE-RULE:END:audit-non-deferrable -->

<!-- SCOPE-RULE:audit-uncertainty -->
Preserve uncertainty in provenance, ownership, dependency, and suspected concerns.
<!-- SCOPE-RULE:END:audit-uncertainty -->

Use these finding classifications:

- `in-scope-required`: the apparent expansion is a necessary direct dependency with explicit
  criterion and provenance support;
- `scope-checkpoint`: the design materially expands authority, absorbs other work, depends on an
  exclusion, or is disproportionate to a smaller viable alternative;
- `defer-candidate`: a verified adjacent concern is independent and needs an existing or new
  owner; and
- `unsupported`: evidence does not support the suspected concern.

Classification is a recommendation for the caller to verify, not a scope decision.

## Report

Write only the requested human-readable report. Do not edit reviewed artifacts, Git state, debt
records, trackers, or implementation files. Include a candidate approved surface even when the
verdict is `needs-attention`, so the caller can disposition unsupported findings without
inventing a surface.

<!-- SCOPE-RULE:audit-report -->
Write one clear approve or needs-attention verdict and sections for promise-to-provenance, component-to-criterion, smallest viable alternative, candidate approved surface, and findings.
<!-- SCOPE-RULE:END:audit-report -->

The candidate approved surface names components/files, changed contracts, an `S`/`M`/`L`
complexity budget with rationale, exclusions, and verified owned deferrals. Each finding records
evidence, impact, recommendation, uncertainty, and one classification.

Return `approve` only when inputs and mappings are complete, the proposal is proportionate, no
`scope-checkpoint` remains, and every deferral candidate has verified independent ownership.
Otherwise return `needs-attention`. Missing or unclear verdicts or semantic sections are
incomplete reports.

<!-- SCOPE-RULE:audit-one-pass -->
Do not rerun unchanged inputs to seek approval.
<!-- SCOPE-RULE:END:audit-one-pass -->

A known or observed reviewed-artifact change or verified ownership change warrants a new pass.
Do not claim detection of arbitrary out-of-band edits, proof of context isolation, or live-model
quality. Add no schema, parser, identifier graph, hash, reservation, or transaction protocol.
