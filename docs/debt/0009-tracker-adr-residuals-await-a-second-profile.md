# 0009 — Tracker ADR residuals await a second profile

## Status

Open
review-by: 2026-11-01

## Concern

Five findings from the adversarial review of ADR 0021 and ADR 0022 were left
unresolved when the review loop was stopped. Each is defensible; none blocks the
GitHub-only work the records currently govern.

1. **Resolution fails open on a malformed declaration, and trackedness is
   asserted but unenforced.** ADR 0021 makes "a declaration in the repo's tracked
   `AGENTS.md`" the sole resolution source and rests its safety argument on that
   file being tracked, but nothing checks trackedness at runtime and a malformed
   declaration has no specified behavior.
2. **The cited precedent differs in the respects under contention.**
   `check-records.sh` + `profiles/{adr,debt}.sh` is invoked as the pattern being
   mirrored, but it is sourced within one script under CI control, where the
   tracker engine is invoked across skills at agent runtime. The cross-skill
   invocation has no precedent in this repo.
3. **Reopen writes an in-flight status but carries terminal consequences**, and
   its failure semantics are unstated — the close write is blocking, and the
   record does not say whether the reverse write is.
4. **No build-vs-buy alternative was considered.** Every rejected option in ADR
   0021 is a way of writing this layer by hand; no existing tool or library was
   weighed.
5. **ADR 0021 runs to roughly twice the repo's ADR norm**, and the excess is
   restatement rather than decision.

## Why deferred

Findings 1, 2 and 3 describe behavior that only becomes observable once a second
profile exists: until then there is one tracker, no declaration is read in
anger, and no reverse projection is written. Sub-issue #46 (Add the Jira tracker
profile) is where each is first exercised, and ADR 0021 already permits the
second profile to amend the contract — so resolving them against a single
implementation would be fixing an interface by guessing at its second consumer.

Finding 4 is a genuine gap in the rejected list, but the search it asks for is
unlikely to change the decision: the layer dispatches between two site-specific
credentials and a repo-local normalized shape, and the cost of evaluating it now
exceeds the cost of recording that it was not evaluated.

Finding 5 was partially addressed; the remaining excess is style, and the review
loop that raised it had begun reporting on text its own fixes wrote.

The loop was stopped under `/review-loop`'s self-collision rule — two successive
passes at half or more findings citing loop-written text — and the operator
authorized one bounded cycle and then proceeding. These five are what remained.

## Non-regression boundary

Sub-project 1 must not make any of these worse. Specifically: the resolution
path must keep failing closed on a declaration naming a tracker with no profile;
the contract suite must keep asserting declared-versus-implemented behavior per
operation rather than mere existence; and no new caller may read Jira native
status for a decision. Adding a second resolution source, or an environment
variable that selects a profile, re-opens finding 1 at higher severity and is
out of bounds.

## What would resolve it

Findings 1–3: `profiles/jira.sh` landing under #46, with the declaration read
against a real Jira-tracked repo, trackedness enforced or explicitly recorded as
unenforceable, and reopen failure semantics settled by what the REST API
actually does. Done when the contract suite covers both profiles and the ADRs
are amended to match observed behavior.

Finding 4: one rejected-alternative entry in ADR 0021, or a note here that the
search was run and found nothing applicable.

Finding 5: a cutting pass on ADR 0021 at the time it is next amended, not as a
standalone change.

## Provenance

target: docs/adr/0021-tracker-abstraction-shape.md
target: docs/adr/0022-canonical-pipeline-state.md
Adversarial review of the tracker ADRs, 2 cycles and 4 passes, 2026-08-01.
Nineteen findings raised, fourteen accepted and fixed, these five deferred.
tracker: #46
