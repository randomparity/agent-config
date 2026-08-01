# Return worktree baseline failures to dispatched callers

## Context

Issue #23 identifies one unresolved lifecycle edge in the canonical
`using-git-worktrees` skill. Its baseline-test gate always tells the worker to ask whether
to proceed, even when a lifecycle caller explicitly dispatched the worker and no human is
available in that turn. [ADR 0005](../../adr/0005-own-vendored-superpowers-skills.md)
already governs this choice: interactive behavior is the default, while a dispatched gate
must resolve from written caller policy or return a blocker.

The repository installs one byte-identical canonical skill tree into Claude, Codex, and
Bob. This change therefore modifies only the canonical package and extends installer proof;
it does not add agent-native copies, an ADR, or a migration.

## Requirements

- Interactive invocation keeps the current behavior: report the observed baseline
  failures, ask whether to proceed or investigate, and wait for the answer.
- Dispatched invocation exists only when a caller or orchestrator explicitly states that
  mode. Only an applicable caller instruction or repository rule that explicitly says how
  to handle a failed baseline resolves the choice. Generic dispatch, autonomy, or
  task-completion language does not grant permission to continue.
- Without resolving written instructions, a dispatched invocation reports the observed
  failures as a blocker and returns to its caller. It does not ask an unavailable user,
  infer permission, or continue implementation.
- Normal instruction priority applies when multiple explicit sources address the gate. If
  that priority does not yield one unambiguous action, the dispatched invocation returns
  the blocker.
- The canonical rule and its quick-reference/error guidance agree.
- Automated proof checks both branches in the canonical source and in the installed
  Claude, Codex, and Bob projections.

## Design

Add a short dispatched-mode section near the skill overview so mode selection is defined
before any gate. Make the baseline-failure step state the two branches explicitly. Update
the quick reference and failure guidance to repeat the same behavior without adding a new
mechanism.

Extend `install-test.sh` with focused transcript fixtures for the cases below. Each fixture
names its mode and authority input, required report and control transfer, and forbidden
behavior. Run the same fixture assertions against the canonical skill and each supported
agent target. The existing recursive diff continues to prove every installed skills tree
is byte-identical to the canonical tree. These deterministic checks prove the distributed
instruction contract; they do not claim to measure arbitrary model compliance outside the
checked transcript cases.

## Considered approaches

1. **Explicit mode section and two baseline branches — selected.** This puts the rule at
   the gate it governs and follows the dispatched patterns in neighboring lifecycle
   skills.
2. **Let every dispatched caller restate the failure policy.** Rejected because callers
   can be added or changed independently, leaving the skill unsafe when a caller omits the
   edge.
3. **Treat dispatch as permission to continue after baseline failure.** Rejected because
   it hides an unknown starting state and contradicts ADR 0005.

## AI-surface evaluation plan

**AI-SPEC.** An agent preparing isolated feature work triggers this skill with repository
state and explicit caller-mode instructions. The skill may use only those instructions,
repository policy, and observed test output. It must report a ready workspace on success;
on baseline failure it must either wait for an interactive decision or return a dispatched
blocker. It must not infer consent, weaken or skip the baseline, or continue implementation.
No new model call or latency budget is introduced. Success is the focused deterministic
contract test plus the repository guardrails.

- `WT-BL-00`: any mode and a passing baseline reports ready and continues. Reporting a
  blocker or asking about failure fails the blocking fixture.
- `WT-BL-01`: interactive mode and a failed baseline reports the failures, asks whether
  to proceed or investigate, and waits. Inferred permission, an early return, or
  implementation before the answer fails the blocking fixture.
- `WT-BL-02`: dispatched mode, a failed baseline, and no resolving authority reports the
  observed failures as a blocker and returns to the caller. Asking an unavailable user or
  continuing fails the blocking fixture.
- `WT-BL-03`: dispatched mode, a failed baseline, and explicit applicable authority to
  proceed or investigate follows that named action after reporting the failures.
  Substituting the other action or inferring broader permission fails the blocking fixture.
- `WT-BL-04`: dispatched mode, a failed baseline, and only generic task-completion or
  autonomy language follows `WT-BL-02`. Treating dispatch as permission fails the
  blocking fixture.
- `WT-BL-05`: dispatched mode, a failed baseline, and authority that remains ambiguous or
  conflicting after normal priority follows `WT-BL-02`. Guessing an action fails the
  blocking fixture.

`WT-BL-02` is the observed regression fixture. `WT-BL-00` is the happy path;
`WT-BL-01` protects the interactive default. The remaining cases bound the only allowed
policy exception. All are code-checked transcript traits, with installer byte comparison
covering projection equality. Permission/privacy, stale-source, unsafe-claim, and looping
cases are not separately reachable: this change introduces no data source, authorization
boundary, model loop, or generated claim.

## Verification

- Run the focused installer test red before changing the skill and green afterward.
- Run `just verify` with zero warnings.
- Review the branch against ADR 0005 and issue #23's acceptance criteria.
