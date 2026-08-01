# Governed Small Change Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an evidence-bearing `governed-small-change` path that reaches TDD before optional design work and fails closed to full design whenever its settled authority is incomplete or invalidated.

**Architecture:** Canonical prompt contracts remain under `content/skills/`. `$work-issue` owns final classification and revalidation, `$build-tdd` accepts the verified no-plan path and returns scope expansion to design, and `$campaign` carries but cannot independently authorize the classification. The existing shell contract suite checks exact bounded rules and one-mutation fixtures.

**Tech Stack:** Markdown Agent Skills, Bash 3.2-compatible regression fixtures, `rg`, `awk`, `just`.

## Global Constraints

- Frozen scope identity: issue 26 plus annotation token `5d738036-9088-4ffe-807a-ab681acfd8c1`.
- `BASE_BRANCH=main`; feature branch is `feat/governed-small-change-26`.
- Canonical reusable workflows live only under `content/skills/`; do not add agent-native skill or command copies.
- Add no dependency and no architecture, schema, persistence, concurrency, authentication, migration, or external-service behavior.
- Keep final branch review, simplification, `just verify`, PR, CI, and merge handoff mandatory.
- Eligibility requires one independently testable implementation slice with no cross-task sequencing or decomposition.
- Missing, superseded, non-accepted, conflicting, incomplete, or no-longer-governing evidence fails closed to full design.
- Local guardrail before every commit and completion: `just verify`.

---

## File structure

- `scripts/check-workflow-scope-contract-test.sh`: owns deterministic extraction,
  mutation, ordering, and fallback fixtures for workflow prompt contracts.
- `content/skills/work-issue/SKILL.md`: owns classification, `WORK:SCOPE` evidence,
  abbreviated-path selection, revalidation, and build-time return to full design.
- `content/skills/build-tdd/SKILL.md`: owns the verified governed no-plan entry and the
  stop/return contract when implementation discovers a new decision.
- `content/skills/campaign/SKILL.md`: owns triage subtype vocabulary and the evidence
  carrier handed to `$work-issue`; it cannot authorize eligibility by name alone.

### Task 1: Prove and implement the governed-small-change contract

**Files:**

- Modify: `scripts/check-workflow-scope-contract-test.sh`
- Modify: `content/skills/work-issue/SKILL.md`
- Modify: `content/skills/build-tdd/SKILL.md`
- Modify: `content/skills/campaign/SKILL.md`

**Interfaces:**

- Consumes: ADR 0007's eligibility predicate and the existing eight-field frozen scope
  carrier.
- Produces: the exact classification literal `governed-small-change`; a bounded
  `SCOPE-RULE` eligibility block in `$work-issue`; campaign verdict evidence fields
  `decision reference`, `decision kind`, `accepted status`, and `governed behavior`;
  and fail-closed transitions to `SCOPE CHECKPOINT` plus full `$design`.

- [ ] **Step 1: Add failing contract assertions**

Extend `check_contract` to resolve `build-tdd` and `campaign`, then assert bounded rules
with exact single-line instructions covering:

```text
Classify as governed-small-change only when one accepted decision governs every changed contract and normative behavior.
Require explicit testable acceptance criteria, no design-changing ambiguity, and one independently testable slice with no cross-task sequencing or decomposition.
Revalidate the decision reference, decision kind, accepted status, and governed behavior when the abbreviated path is consumed.
Missing, superseded, non-accepted, conflicting, incomplete, or no-longer-governing evidence returns to SCOPE CHECKPOINT and full design.
A governed-small-change proceeds from verified WORK:SCOPE directly to build-tdd without a new spec or plan.
Build-time scope expansion stops implementation, re-freezes scope, and runs full design without automatically reselecting the abbreviated path.
Campaign carries governed-small-change evidence to work-issue; the subtype name alone never authorizes the abbreviated path.
```

Add isolated mutations for at least these three named regressions:

1. replace the direct-to-`build-tdd` instruction with a new-spec requirement;
2. replace the ambiguity fallback with shortcut selection; and
3. replace the build-time scope-expansion return with an instruction to infer and
   continue.

Add separate mutations that remove campaign evidence/revalidation and post-build phase
preservation. Add a bounded `SCOPE-ORDER` marker for abbreviated-path selection, assert
with `assert_ordered_clause` that selection precedes `work-design`, and add a mutation
that moves the selection marker after `work-design`. Update the exact fixture count. Use
existing `copy_fixture`, `rewrite_block_line_once`, `move_marker_after`, `assert_rule`,
`assert_ordered_clause`, and `assert_fixture_fails`; do not add another test framework.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
./scripts/check-workflow-scope-contract-test.sh
```

Expected: non-zero with the first missing governed-small-change rule or carrier assertion,
not a shell syntax or fixture-harness error.

- [ ] **Step 3: Add the minimal canonical workflow rules**

In `content/skills/work-issue/SKILL.md`:

- expand the classification list to three ordered classes;
- make `governed-small-change` require every predicate and evidence field above;
- record classification and evidence in `WORK:SCOPE` and verify them on readback;
- allow only trivial and governed-small changes to skip step 3;
- revalidate eligibility immediately before the abbreviated build path; and
- route failed revalidation or build-time expansion through `SCOPE CHECKPOINT`, a
  re-frozen charter, and full `$design` without automatic shortcut reselection.

In `content/skills/build-tdd/SKILL.md`, replace the binary no-plan gate with:

```text
No plan is valid only for a trivial bugfix or a caller-verified governed-small-change.
For the governed path, write and run the focused failing test first. If implementation
discovers a new decision or scope expansion, stop and return to the caller's scope
checkpoint; do not infer the decision or continue building.
```

In `content/skills/campaign/SKILL.md`:

- add `governed-small-change` to the `fix` subtype enum and planning vocabulary;
- require its structured triage verdict to cite decision reference, kind, accepted
  status, governed behavior, and explicit acceptance criteria;
- carry those fields verbatim in the `$work-issue` dispatch prompt; and
- state that `$work-issue` revalidates them and falls back to `non-trivial` when stale,
  conflicting, or incomplete.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
./scripts/check-workflow-scope-contract-test.sh
```

Expected: exit 0 with the updated fixture total and zero fixture failures.

- [ ] **Step 5: Prove each fixture bites**

Temporarily reverse one new exact rule in the copied fixture construction so the mutated
fixture matches canonical text, run the focused test, and confirm it fails because that
mutation unexpectedly passed. Restore the fixture mutation and rerun to green. Do not
alter canonical skill text for this proof.

- [ ] **Step 6: Run repository guardrails**

Run:

```bash
just verify
git diff --check
```

Expected: both exit 0 with zero warnings.

- [ ] **Step 7: Review the diff and commit**

Confirm the staged implementation delta contains only the four task files, prompt rules
match ADR 0007, campaign carries evidence rather than authority, and no post-build phase
was weakened. The full branch diff may additionally contain the committed issue 26 spec,
ADR, and implementation plan. Then run:

```bash
git add scripts/check-workflow-scope-contract-test.sh \
  content/skills/work-issue/SKILL.md \
  content/skills/build-tdd/SKILL.md \
  content/skills/campaign/SKILL.md
git commit -m "feat: add governed small change workflow"
```

Expected: the pre-commit `just verify` hook passes and one implementation commit is
created.

## Completion checkpoint

- [ ] Every issue 26 criterion maps to Task 1.
- [ ] No incomplete step, placeholder, agent-native skill copy, or new dependency exists.
- [ ] The plan, ADR, and spec contain every design decision needed after compaction.
- [ ] Branch `feat/governed-small-change-26`, base `main`, and guardrail `just verify`
  remain recoverable from this plan.
