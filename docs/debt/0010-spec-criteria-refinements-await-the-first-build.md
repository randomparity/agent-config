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

5. **bash 3.2 compatibility is asserted but never exercised.** The plan's global
   constraints require it — macOS ships 3.2 as `/bin/bash`, and `"${arr[@]}"` on
   an empty array is fatal there under `set -u` — and this is the repo's first
   shell code using arrays. Every run so far has been under the host's bash 5.
   Nothing proves the claim.

6. **`target-url` failure diagnostics are captured and discarded.**
   `create-verified-issue.sh` captures the tracker's stderr, then on failure
   prints only "canonical repository URL could not be resolved for <repo>" and
   never emits what it captured. The engine does classify the failure — auth,
   not-found or transport, with gh's message — so the information exists and is
   dropped one frame later. An operator sees a generic line where a specific one
   was available.
7. **The absent-label idempotency assertion cannot fail under its stub.** The
   suite asserts that `label-edit --remove not-present` exits zero, but the stub
   in force exits zero for anything, and models no notion of which labels an
   issue carries. The assertion holds for any argument and would keep passing if
   the behavior regressed.

## Why deferred

The first four are questions about how to *test* a layer that did not exist
when they were raised, and each has a cheap empirical answer now that it does. Findings 1 and 4 in particular
ask for a stubbing design — how the fixture distinguishes an auth failure from a
transport failure, and how the suite proves no egress — that is better settled by
writing the stub than by specifying it in advance; the spec would otherwise fix a
technique the implementation then has to work around.

Finding 3 needs the call sites: the bound `search` requires is whatever
`/issue`'s dedup, `/campaign` and `/groom` actually need, and those migrate in
sub-projects 5 and 6, where a wrong guess made now would be discovered late.

Findings 6 and 7 are observability and test-strength gaps that cannot produce a
wrong write: 6 loses detail from a message that already fails correctly, and 7 is
an assertion weaker than it reads rather than a wrong one. They were left when
the branch review was stopped under its self-collision rule — four passes at
13, 7, 8 and 7 findings, with each round's highest-severity item introduced by
the previous round's fix. The operator chose to stop and record rather than run
a fifth pass.

Finding 5 needs a bash 3.2 to run against, which this host does not have. The
empty-array expansions are individually guarded (`"${arr[@]+"${arr[@]}"}"`), so
the risk is a missed site rather than a known break; a CI job on macOS, or a
pinned bash 3.2 container, is what would settle it.

None of the first four can produce a wrong write against a live tracker. They bound
how much confidence the gate carries, not whether the layer is correct.

Findings 1 to 4 come from the spec review, stopped under the same
self-collision pattern as the record review: findings rose from eight to eleven
across two passes with roughly two-thirds citing text the loop's own fixes had
written. The operator authorised proceeding to implementation. Seven of the
eleven were fixed, including every finding that could cause a wrong write.
Finding 5 comes from the branch review that followed.

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

Finding 6: pass the engine's classified stderr through to the operator, so an
auth failure against the canonical-URL read is distinguishable from a network
one. Finding 7: give the stub a notion of which labels an issue carries, so the
assertion can fail. Both are small and belong with the next change that touches
those paths.

Finding 5: running `tracker-test.sh` and `create-verified-issue-test.sh` under a
real bash 3.2 — a macOS CI leg or a pinned container — and fixing whatever it
reports. Done when the suite is green on 3.2 as well as 5.

## Provenance

target: docs/superpowers/specs/2026-08-01-tracker-agnostic-issue-pipeline-design.md
Adversarial review of the tracker design spec (2 passes) and of the branch
(3 passes), 2026-08-01. Findings 1 to 4 deferred from the spec review, finding 5
from the branch review.
tracker: #43
