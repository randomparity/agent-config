# 0010 — Spec criteria refinements await the first build

## Status

Open
review-by: 2026-10-01

## Concern

Four findings from the second adversarial review of the tracker design spec were
left unresolved when the review loop was stopped. Each is defensible; none
blocks starting sub-project 1.

1. **Acceptance criterion 4 is unsatisfiable as written**, so a reviewer cannot
   check it. It requires every exit class in the failure taxonomy to be
   triggered and asserted, but two classes — `auth` and `transport` — are not
   reachable from a hermetic suite without the stub itself deciding which class
   the engine reports, which tests the fixture rather than the engine.
2. **Criterion 2 cannot detect the exit-code regression the new taxonomy makes
   likely.** `create-verified-issue-test.sh` passing unmodified proves the
   script's own diagnostics survive, but it exercises the engine only through
   that one caller, so a wrong exit *class* on an operation it does not call
   goes unseen.
3. **`search` has no result bound or completeness semantics**, and `/issue`'s
   dedup gate reads its result as complete. A truncated result set would read as
   "no duplicate found".
4. **Criterion 6's stated verification does not establish the hermeticity it
   claims.** Unsetting the tokens and asserting exit zero proves the suite does
   not *require* credentials; it does not prove the suite makes no network call,
   which is the property that keeps it running in CI.

## Why deferred

All four are questions about how to *test* a layer that does not exist yet, and
each has a cheap empirical answer once it does. Findings 1 and 4 in particular
ask for a stubbing design — how the fixture distinguishes an auth failure from a
transport failure, and how the suite proves no egress — that is better settled by
writing the stub than by specifying it in advance; the spec would otherwise fix a
technique the implementation then has to work around.

Finding 3 needs the call sites: the bound `search` requires is whatever
`/issue`'s dedup, `/campaign` and `/groom` actually need, and those migrate in
sub-projects 5 and 6, where a wrong guess made now would be discovered late.

None of the four can produce a wrong write against a live tracker. They bound
how much confidence the gate carries, not whether the layer is correct.

The loop was stopped under the same self-collision pattern as the ADR review:
findings rose from eight to eleven across two passes with roughly two-thirds
citing text the loop's own fixes had written. The operator authorised proceeding
to implementation. Seven of the eleven were fixed, including every finding that
could cause a wrong write; these four remained.

## Non-regression boundary

Sub-project 1 must not weaken what the criteria already guarantee. Specifically:
the contract suite must keep running with no credentials present; every
operation must keep asserting its success shape and at least the `not-found` and
`usage` exit classes; and `create-verified-issue-test.sh` must keep passing
unmodified. Narrowing any of these to make the suite simpler re-opens these
findings at higher severity.

## What would resolve it

Findings 1 and 4: the stub design landing in `tracker-test.sh` under #43, with
the criteria rewritten to assert what the stub can actually establish — and an
explicit no-egress check if one proves cheap, or a recorded note that it does
not.

Finding 2: contract-suite coverage of exit classes per operation, which #43
already owes under its criterion 4; this finding is the observation that
criterion 2 alone does not carry it.

Finding 3: a result bound and a truncation signal on `search`, decided against
the real call sites when they migrate under #47 and #48.

## Provenance

target: docs/superpowers/specs/2026-08-01-tracker-agnostic-issue-pipeline-design.md
Adversarial review of the tracker design spec, 2 passes, 2026-08-01.
Nineteen findings raised across both passes, fifteen accepted and fixed, these
four deferred.
tracker: #43
