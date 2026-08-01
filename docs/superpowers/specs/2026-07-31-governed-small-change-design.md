# Governed Small Change Workflow Design

## Purpose and authority

Issue 26 requests a proportional pre-code workflow for small changes whose behavior is
already settled. The frozen authority is its verified `WORK:SCOPE` annotation with token
`5d738036-9088-4ffe-807a-ab681acfd8c1`; issue 26 supplies every normative criterion. This
design is governed by [ADR 0007](../../adr/0007-governed-small-change-path.md).

In scope are the canonical `$work-issue` classification, campaign handoff of that
classification, and deterministic workflow-contract fixtures. Final review,
simplification, guardrails, PR, CI, and merge handoff remain unchanged. Agent-native trees,
new dependencies, and new architecture, schema, persistence, concurrency, authentication,
migration, or external-service decisions are out of scope.

## Approaches

### Selected: strict evidence-bearing third classification

`$work-issue` adds `governed-small-change` beside `trivial bugfix` and `non-trivial
change`. Eligibility requires all of:

1. a linked accepted ADR or equivalent settled decision governs the behavior;
2. the issue has explicit, testable acceptance criteria;
3. no unresolved design-changing ambiguity exists; and
4. implementation introduces no new architecture, schema, dependency, persistence,
   concurrency, authentication, migration, or external-service decision; and
5. the work is one independently testable implementation slice that one PR can deliver
   without cross-task sequencing or decomposition.

The workflow records the evidence and classification in `WORK:SCOPE`, creates its branch,
then proceeds directly to `$build-tdd`. The existing branch-wide review and shipping
phases remain mandatory. If implementation discovers a new decision or scope expansion,
the current build stops and returns to `SCOPE CHECKPOINT`; after the charter is re-frozen,
the full `$design` phase runs before implementation resumes.

Campaign triage gains the same third fix subtype. Its structured verdict cites the
governing decision and acceptance criteria, and the `$work-issue` subagent independently
rechecks eligibility against the live issue before preserving it. Missing or stale
evidence falls back to `non-trivial`.

The evidence carrier records the stable decision reference, its decision kind, its
authoritative accepted status, and the behavior or contract it governs. An ADR is checked
against its `Status` section and any supersession banner under the repository's
decision-record convention.
An equivalent decision is eligible only when the repository already defines an equally
durable, independently checkable acceptance and supersession convention; this change does
not create one. Campaign carries those evidence fields verbatim. `$work-issue` resolves the
reference again, confirms its accepted and non-superseded state, checks the claimed governed
behavior against the live issue criteria, and fails closed to `non-trivial` when any field
is absent, conflicting, or cannot be revalidated.

### Rejected: caller-selected shortcut

Allowing a flag or prompt phrase to skip design creates a second authority mechanism and
does not prove that the decision is settled.

### Rejected: heuristic inference

File count, effort labels, or issue length can estimate cost but cannot establish that no
new public contract or architectural choice is being made.

## Workflow contract

Classification happens before `WORK:SCOPE`. The annotation retains the existing eight
charter fields and tracking metadata and also states the selected class plus, for a
governed small change, the governing decision evidence. Only `trivial bugfix` and
`governed-small-change` skip step 3. The latter remains non-trivial in blast-radius and
risk reporting; it is an execution-path classification, not a claim that the contract is
private or risk-free.

`$build-tdd` accepts the absence of a plan when the caller identifies a verified governed
small change. It starts with the issue's focused regression test. It does not invent a
plan artifact merely to satisfy its current non-trivial guard. Discovery of a decision
outside the governing record is a scope checkpoint, not an implementation assumption.

Campaign's triage report contract and model-selection text recognize
`governed-small-change`. The dispatch prompt carries evidence rather than merely the
classification name. `$work-issue` remains the final gate and fails closed to full design
if the evidence no longer matches the issue.

## Requirement provenance

| Guarantee | Authority |
|---|---|
| Governed small changes may proceed from frozen scope to TDD | Issue 26 Expected 1–2 and Proposed 1–3 |
| Full design handles ambiguity, architecture, and scope expansion | Issue 26 Expected 3 and Proposed 2, 6 |
| Branch review, simplification, guardrails, PR, and CI remain mandatory | Issue 26 Expected 2 and Proposed 4 |
| Campaign preserves evidence-bearing classification | Issue 26 Proposed 5 |
| Three named regressions are deterministic fixtures | Issue 26 Proposed 6 |

## AI-SPEC

The user is an operator invoking `$work-issue` directly or through `$campaign`. The trigger
is issue classification before branch work. Inputs are the frozen issue authority, linked
accepted decisions, acceptance criteria, and repository evidence. Output is one of three
classifications and the next workflow phase. Allowed sources are those external artifacts;
the workflow must not treat its own generated prose, a label, or caller preference as
settled design authority. Missing or conflicting evidence falls back to full design; scope
expansion returns to the scope checkpoint. No model call or dependency is added, so cost
and latency remain those of the existing workflow. Success is deterministic contract
coverage plus the unchanged final review and CI gates.

The classification decision is ordered and fail-closed:

1. If the work requires decomposition or cross-task sequencing, select `non-trivial` and
   run full design. File count, effort labels, and issue length may inform that check but
   cannot establish eligibility by themselves.
2. If any governing-decision evidence cannot be revalidated, any acceptance criterion is
   implicit or untestable, or any design-changing ambiguity remains, select `non-trivial`
   and run full design.
3. Otherwise, if implementation would introduce any excluded decision category, select
   `non-trivial` and run full design.
4. Only when every eligibility predicate succeeds, select `governed-small-change` and make
   the focused failing test the next executable phase.
5. If build-time discovery invalidates any prior conclusion, stop the build, return to
   `SCOPE CHECKPOINT`, re-freeze the charter, and run full design without automatically
   reselecting the abbreviated path.

## Failure modes and eval cases

| ID | Failure mode | Severity | Fixture and observable gate |
|---|---|---:|---|
| GSC-1 | Accepted decision and explicit criteria still force a new spec | 4 | An issue shaped like #23 selects `governed-small-change` and reaches a failing focused test before any new spec; block otherwise. |
| GSC-2 | Small wording hides an unresolved contract decision | 4 | A small issue with ambiguous external behavior selects `non-trivial` and full design; block on shortcut. |
| GSC-3 | Implementation expands beyond the governing record | 5 | A discovered new decision returns `SCOPE CHECKPOINT` and full design; block if implementation infers it. |
| GSC-4 | Caller or label bypasses evidence | 5 | Missing governing-decision evidence falls back to `non-trivial`; block on caller-selected shortcut. |
| GSC-5 | Campaign drops or fabricates eligibility evidence | 4 | Campaign verdict and dispatch contracts carry evidence, and `$work-issue` rechecks it; block on name-only propagation. |
| GSC-6 | Abbreviated path skips post-build controls | 5 | Ordered-clause fixtures retain review, simplification, verification, PR, and CI phases; block on omission. |
| GSC-7 | Stale or conflicting decision evidence is accepted | 4 | Superseded, non-accepted, or conflicting evidence falls back to full design; block on abbreviated path. |
| GSC-9 | Workflow loops between build and design | 4 | One scope-expansion transition re-freezes scope and resumes through full design, with no automatic repeated bypass; block on loop. |
| GSC-10 | A broad but fully governed change skips planning | 4 | A change requiring decomposition or cross-task sequencing selects `non-trivial` even with accepted decision evidence and explicit criteria; block on shortcut. |

Measurements are structure-aware shell assertions over canonical skill text and isolated
mutated fixtures. The fixtures encode the ordered decision table above and the three issue
26 scenarios, then assert the documented class, next phase, evidence carrier, and fallback
clauses; mutations remove or reorder one guard at a time to prove each assertion bites. They
also assert that the failing-test instruction precedes optional elaboration and that all
post-build controls remain ordered after the abbreviated path. These tests prove the
workflow contract supplied to an agent, not live model adherence to that contract. Final
branch review and CI remain the behavioral backstops; no LLM judges or live external
services are added.

## Verification and durable handoff

The implementation adds focused assertions to
`scripts/check-workflow-scope-contract-test.sh`, then runs that test red before changing
canonical skills and green afterward. Completion runs `just verify` with zero warnings.
The implementation plan records `BASE_BRANCH=main`, branch
`feat/governed-small-change-26`, and `just verify` as the local guardrail for resumption.
