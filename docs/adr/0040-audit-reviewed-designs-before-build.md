# 0040 -- Audit reviewed designs before implementation

## Status

Accepted (2026-08-10)

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

Add a reusable, prose-only `scope-audit` skill. For every `work-issue` run that enters the
full design path, a fresh independent agent reads the complete frozen charter, every reviewed
ADR, specification, and plan associated with that run, and linked ownership as one proposed
change after design review and before TDD. A missing or unresolved expected artifact returns
`needs-attention`. The caller enumerates the set, and the independent auditor cross-checks it
against the branch diff and linked work evidence without adding a discovery schema. Uncertain
completeness remains uncertain and returns `needs-attention`. The audit writes a human-readable
report as per-worktree state under `.agent/scope-audit/`, with `approve` or `needs-attention`
inside that report. The caller supplies a fresh report path and reads the resulting document
before TDD. A missing report, missing verdict, or absent required semantic section stops before
TDD. This is a prose handoff, not an identity, reservation, or transaction protocol.

The observable trigger is entry into `work-issue`'s full design path: any run that produces
or consumes reviewed design artifacts runs the audit before TDD. Existing trivial-bugfix and
governed-small-change paths, which do not enter design, remain exempt.

The report maps promises to external provenance and components to criteria, compares the
smallest viable alternative, classifies findings, and records a compact approved surface of
components, contracts, complexity, exclusions, and owned deferrals. It is evidence, not
authority. Before changing a reviewed artifact, the caller applies the existing
`receiving-code-review` workflow separately to each finding's concern and proposed remedy.
A valid concern does not validate its recommendation. The caller records `accepted-fixed`,
`rejected-with-evidence`, `deferred-tracked`, or `blocked`; no edit precedes that disposition.
Reviewer severity, repetition, classification, and review-created text do not supply scope
authority. Material expansion returns to `SCOPE CHECKPOINT`; independent adjacent concerns
use the existing debt and tracker workflow; depended-on or worsened concerns cannot be
deferred. The report preserves uncertainty in provenance, ownership, and dependency
classification. A link or plausible owner is not verification; only a verified independent
owner may appear as an owned deferral. Branch review compares the diff with the approved
surface and applies the same reception gate to its findings.

Per ADR 0038 the phase prose is not gated for its wording. The charter carrier the dispatch
carries is machine-read, so `scripts/check-carrier-drift.sh` pins it byte for byte, and the
existing installed-projection test covers the new skill. The workflow adds
no formal result schema, parser, artifact identity graph, content hashing, transaction
protocol, or live-model evaluation subsystem. A design change the workflow makes or observes
invalidates the report and requires another audit. Detecting arbitrary out-of-band edits is
not guaranteed without the excluded identity machinery.

## Consequences

- Aggregate scope is challenged before implementation cost is sunk.
- The audit adds one independent model pass to issue work that enters the full design path.
- Its Markdown report follows ADR 0027's self-ignored `.agent/` convention, so it survives a
  session boundary without becoming committed product documentation.
- Reviewers and operators, rather than a new parser, judge the report's substantive quality.
- No gate asserts that the phase's rule sentences survive a rewrite. Under ADR 0038 that is
  the accepted cost of gating meaning over wording: the dispatch carrier is pinned, and the
  rules around it are reviewed by humans at review time.
- A resumed workflow must inspect its design state, but the prose report cannot prove that no
  unobserved out-of-band edit occurred.
- The report does not prove that no concurrent or out-of-band writer changed its contents.

## Considered & rejected

- **Embed the check in `work-issue`.** A fresh subagent could still be independent, but the
  audit would not provide the reusable workflow entry point issue #94 requires.
- **Build a formal schema and validator.** Rejected because referential identifiers, parsing,
  artifact hashes, and consistency machinery are disproportionate to a prose workflow.
- **Rely on post-build branch review.** Rejected because it discovers aggregate scope failure
  only after implementation cost is sunk.
- **Keep the existing workflow.** Rejected because issue #94 explicitly requires pre-build
  detection; accepting the known late-detection cost does not satisfy that outcome.
