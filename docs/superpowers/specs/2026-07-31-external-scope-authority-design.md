# External Scope Authority Design

## Purpose

Issue 24 prevents design workflows from strengthening a user's requirement without
explicit authority. The workflow must preserve the distinction between permission to
review a design and permission to expand the product contract.

This design is governed by [ADR 0005](../../adr/0005-external-scope-authority.md).

## Frozen scope and assumptions

The external authority is issue 24 and the single complete `WORK:SCOPE` annotation posted
before this design began. Issue 17 and PR 22 demonstrate the failure mode but add no
requirements. A later generated annotation cannot replace this charter. Only an explicit
user decision can change it; that decision is added to provenance and design restarts or
re-freezes against the changed charter.

In scope:

- publish the complete scope charter before design;
- distinguish an interactive root workflow from genuinely unattended dispatch;
- return design-changing questions through an interactive caller;
- trace normative guarantees to external authority or necessary consequences;
- make design-time review inherit the external charter;
- prefer removing an ungrounded guarantee over adding controls for it; and
- add deterministic regression coverage for the requested scenarios.

Out of scope:

- transaction, persistence, concurrency, recovery, migration, or other new product
  guarantees not requested by issue 24;
- redesigning the installer delivered for issue 17;
- a runtime policy engine, a second scope-record format, or a new dependency; and
- live-model grading, which would be nondeterministic and require an external service.

Assumption: the root workflow knows whether it has an interactive user because the root
invocation establishes that fact. Skill nesting does not change it. When no human is
reachable, a design-changing ambiguity is parked rather than resolved by inventing a new
normative guarantee.

## Approaches

### Selected: external charter plus propagated human availability

`$work-issue` writes the expanded `WORK:SCOPE` record immediately after issue scoping and
before `$design`. The record is the durable external charter. The root invocation also
establishes whether a human is reachable; nested skills inherit that value. `$design` and
its reviews trace every normative guarantee back to this charter.

This directly closes both failure paths without introducing executable state or another
workflow surface.

### Rejected: stronger reviews over the existing spec-derived charter

This could catch obvious over-design, but the reviewed spec would remain its own authority.
A self-consistent expanded contract could still pass.

### Rejected: executable scope-policy engine or live-model evaluator

An engine would duplicate the skill prose and create a second policy mechanism. A live
grader would add cost, nondeterminism, credentials, and an external dependency. Neither is
necessary to preserve the requested authority boundary.

## Workflow contract

### Freeze scope before design

`$work-issue` publishes `WORK:SCOPE` after classification and before branch design work.
The annotation retains blast radius, risk flags, complexity, and decomposition, and adds:

- requested outcome and completion criteria with provenance;
- explicit exclusions;
- permitted change surface; and
- unresolved design-changing ambiguities.

If an ambiguity would change the design, the interactive root asks the user before
publishing a complete scope record. A genuinely unattended root records the ambiguity,
posts the required trajectory note, and parks as `status:needs-human`; it does not start
design with an unresolved charter. Existing historical annotations are not rewritten.

### Propagate interaction context

`$brainstorming`, `$design`, and `$writing-plans` stop treating curated-skill nesting as
proof that no human is present. They use two explicit contexts:

- **interactive root:** nested skills return design-changing questions to their caller,
  which asks the user and resumes with the answer; and
- **unattended root:** approval gates use the already frozen requirement, but any new
  design-changing ambiguity returns to the caller for parking.

Each supported root resolves and states `interaction: interactive` when a human invoked it
in the active turn, or `interaction: unattended` only when an orchestrator or background
task explicitly says no human is reachable. Every nested skill call carries that exact
field, the charter's durable identity, and the complete frozen outcome, completion
criteria, provenance map, exclusions, permitted surface, and ambiguity list. The
provenance map ties each outcome, criterion, and later explicit user decision to its
issue, comment, or quoted direct-user source. Nesting never recomputes these fields. The
identity is the `WORK:SCOPE` comment for issue work or the quoted direct user request for
standalone design.

When a nested skill finds a design-changing ambiguity, it returns this prompt-level block
to its caller instead of resolving the question:

```text
SCOPE CHECKPOINT
interaction: <interactive or unattended, unchanged from the root>
scope identity: <frozen WORK:SCOPE comment or quoted direct request>
outcome: <frozen requested outcome>
completion criteria: <frozen completion criteria>
provenance: <source for each outcome, criterion, and later explicit user decision>
exclusions: <frozen exclusions>
surface: <frozen permitted change surface>
ambiguities: <frozen unresolved ambiguity list>
question: <one question whose answer selects the design>
why design-changing: <scope field or normative guarantee affected>
```

An interactive root asks the returned question, records the answer in provenance, and
re-freezes before continuing. An unattended root records the same block in
`WORK:TRAJECTORY` and parks as `status:needs-human`. This is an instruction and return
contract between skills, not a runtime state store or policy engine. A missing,
unresolvable, or incomplete charter—including absent provenance—returns this checkpoint
(or parks an unattended root); a nested skill never falls back to deriving authority from
the artifact under review.

### Trace normative guarantees

`$design` treats a statement as normative when downstream implementation or review would
be required to preserve it. Each normative guarantee in a spec or ADR must identify one
of these sources:

1. a requirement or completion criterion in the frozen scope;
2. an explicit user decision appended to the scope provenance; or
3. a necessary consequence, with reasoning that no reasonable implementation can satisfy
   the sourced completion criterion without it.

The spec carries a compact provenance section or inline source references. An untraceable
guarantee, or a claim of necessity that a reasonable alternative makes contestable, is a
design-changing question. An interactive root asks; an unattended root parks.
Transactions, persistence, concurrency, recovery, migrations, and new public contracts are
named high-risk examples, not an exhaustive exception list.

### Keep review authority external

Design-time `$review-loop` charters come from the frozen scope supplied by the caller, not
from the spec, ADR, or plan under review. Those documents may refine implementation detail
within the permitted surface but cannot expand the charter. Authorization to run another
review or address findings leaves the charter unchanged.

`$challenge` reports an ungrounded normative guarantee as scope expansion. Its first
recommendation is to delete or weaken that guarantee. It recommends implementation
machinery only when the frozen scope or an explicit user decision authorizes the promise.

## Requirement provenance

| Normative guarantee | Authority |
|---|---|
| Scope is complete and published before design | Issue 24 Expected 1–2 and Proposed 1–2 |
| Nested interactive skills retain a user path | Issue 24 Expected 1 and Proposed 3 |
| Every normative design requirement is traceable | Issue 24 Expected 3 and Proposed 4 |
| Design reviews use an external charter | Issue 24 Expected 4 and Proposed 5 |
| New high-risk contracts require human approval | Issue 24 Expected 5 |
| More review does not expand scope | Issue 24 Expected 6 |
| Ungrounded promises are removed before machinery is added | Issue 24 Expected 7 and Proposed 6 |
| Deterministic fixtures cover the named regressions | Issue 24 Proposed 7 |

No additional product guarantee is a necessary consequence of these workflow rules.

## AI-SPEC

The user is an operator invoking issue, design, and review workflows. The trigger is a
design phase or design review. Inputs are the user request, issue text, explicit user
decisions, the frozen `WORK:SCOPE` record, and repository evidence. Outputs are a scoped
specification, ADR when warranted, plan, questions returned to an interactive caller, or
a parked unattended workflow. Allowed sources are those external inputs and necessary
consequences explained in the design. The workflow must not treat its own generated spec,
additional review authorization, or reviewer suggestions as product-scope authority. When
authority is missing it asks through an interactive caller or parks unattended work. It
adds no model calls, so latency and cost remain those of the existing workflow. Success is
the deterministic contract suite plus adversarial review finding no self-authorized
guarantee in the branch.

## Failure-mode map

| Failure mode | Severity | Control |
|---|---:|---|
| Generated spec becomes its own authority | 5 | external frozen charter and provenance review |
| Nested interactive call loses access to the user | 4 | root interaction context propagates downstream |
| Unattended workflow guesses through a design-changing ambiguity | 4 | return-and-park rule |
| Repeated review authorization mutates scope | 5 | externally sourced charter stays unchanged through the existing bounded review cycle |
| Explicitly requested atomic behavior is rejected as scope creep | 4 | explicit user decisions are valid provenance |
| A reviewed artifact, including an unrelated permission or private-data claim, conflicts with the frozen scope | 5 | the complete pre-design charter is carried into review; explicit user change re-freezes it |
| Reviewer adds controls for an ungrounded promise | 4 | delete-or-weaken-first challenge rule |

## Eval cases

The fixtures are deterministic contract-structure checks over the composed canonical
skills. They prove that the source clauses and handoff ordering remain present; they do not
observe or predict a live model's response. Each fixture copies the named skills, confirms
the stated oracle, removes or reorders one required clause, and must then fail.

| ID | Prompt-contract setup | Deterministic oracle | Required negative mutation | Gate |
|---|---|---|---|---|
| SCOPE-01 | One canonical source is requested; a spec proposes transactions | `$design` requires provenance and `$challenge` says delete or weaken an ungrounded promise first | remove the delete-or-weaken rule | block |
| SCOPE-02 | Atomic installation is explicitly requested | `$design` names an explicit user decision as valid provenance before it names high-risk contract examples | remove explicit-user-decision provenance | block |
| SCOPE-03 | Interactive `$work-issue` nests `$design` | root sets `interaction: interactive`; nested call carries the complete charter including provenance and can return it in `SCOPE CHECKPOINT` | omit provenance, pass only a charter reference, or restore nesting-based unattended inference | block |
| SCOPE-04 | Operator repeatedly authorizes review up to the existing cycle cap | `$review-loop` states that review authorization leaves its externally sourced charter unchanged | remove the unchanged-charter clause | block |
| SCOPE-05 | Unattended root reaches ambiguity | `SCOPE CHECKPOINT` precedes trajectory-note and `status:needs-human` parking instructions | remove or reorder the parking handoff | block |
| SCOPE-06 | Stale reviewed spec proposes an unrelated permission or private-data claim that conflicts with its pre-design charter | `$review-loop` receives the complete external charter and provenance, and forbids target-derived fallback; `$challenge` treats the ungrounded claim as expansion | omit provenance, pass only an identity, or derive authority from the review target | block |

SCOPE-01 is the observed issue 17 regression. SCOPE-03 is the ambiguous-input case.
SCOPE-06 covers stale/conflicting generated content, forbidden claims, and the
permissions/privacy boundary. SCOPE-04 exercises repeated review only within the existing
hard cap. SCOPE-02 proves the contract is not a blanket ban on complex designs. SCOPE-05
is the unattended counterpart explicitly required by issue 24's nested-versus-background
distinction; it adds no product behavior beyond the workflow's existing parking path.

## Verification design

A focused shell test under `scripts/` copies the canonical skills into a temporary fixture
root and checks the contract directly. It asserts pre-design ordering in `$work-issue`,
the explicit `interaction:` and complete-charter carrier including provenance, the
`SCOPE CHECKPOINT` return path, the provenance rule, the external review charter, and the delete-or-weaken
recommendation. For every SCOPE case, the test applies the named negative mutation and
asserts that the same oracle fails. The test joins the existing `just test` recipe and
therefore `just verify`/CI. No new dependency is added, and its report calls the result
prompt-contract coverage rather than model-behavior coverage.

The implementation follows TDD: add the focused test and observe it fail against the
current skills; make the smallest skill edits that satisfy it; then run the focused test,
`just verify`, and `prek run --all-files`.

## Rollback

Before merge, revert the branch commits. After merge, revert the workflow and test commits
together. No persisted format, generated state, migration, or external service must be
reconciled.

## Durable execution context

- Branch: `feat/prevent-scope-expansion-24`
- Base branch: `main`
- Local guardrail: `just verify`
- CI guardrail: `just ci` (includes `just verify` and `prek run --all-files`)
- Decision-record index coupling: not coupled; the repository uses directory listings.
