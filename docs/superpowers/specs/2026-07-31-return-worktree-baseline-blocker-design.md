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
  mode. Written caller instructions may resolve the failure choice.
- Without resolving written instructions, a dispatched invocation reports the observed
  failures as a blocker and returns to its caller. It does not ask an unavailable user,
  infer permission, or continue implementation.
- The canonical rule and its quick-reference/error guidance agree.
- Automated proof checks both branches in the canonical source and in the installed
  Claude, Codex, and Bob projections.

## Design

Add a short dispatched-mode section near the skill overview so mode selection is defined
before any gate. Make the baseline-failure step state the two branches explicitly. Update
the quick reference and failure guidance to repeat the same behavior without adding a new
mechanism.

Extend `install-test.sh` with a focused contract assertion. It checks the distinctive
interactive and dispatched instructions in the canonical skill, then applies the same
assertion after installation to each supported agent target. The existing recursive diff
continues to prove every installed skills tree is byte-identical to the canonical tree;
the focused assertions make the lifecycle contract legible when they fail.

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

| Failure mode | Severity | CI evidence |
|---|---:|---|
| Dispatched worker waits for a user | 4 | canonical and installed copies contain the return-a-blocker branch |
| Dispatched worker infers permission and continues | 4 | blocker branch explicitly forbids inference and continuation |
| Interactive invocation loses its decision gate | 4 | canonical and installed copies retain report, ask, and wait behavior |
| One agent receives different instructions | 4 | each target is contract-checked and byte-compared with the canonical tree |

The observed regression is the dispatched baseline-failure case. The corresponding happy
path is the existing passing-baseline report. Ambiguous or conflicting written caller
policy is not permission and therefore falls back to a blocker. Permission/privacy,
stale-source, unsafe-claim, and looping cases are not reachable: this change introduces
no data source, authorization boundary, model loop, or generated claim.

## Verification

- Run the focused installer test red before changing the skill and green afterward.
- Run `just verify` with zero warnings.
- Review the branch against ADR 0005 and issue #23's acceptance criteria.
