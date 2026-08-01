# 0002 — Non-lifecycle vendored skills retain human-only gates

## Status

Open
review-by: 2026-10-31

## Concern

Issue #13 requires this migration to audit the deployed vendored testing, debugging,
review-reception, and verification skills. Within that boundary, several skills still
direct a dispatched worker to an unavailable human:

- `test-driven-development/SKILL.md` makes test-first exceptions conditional on human
  permission and sends an unknown test strategy to the human. These executable gates are
  present in the Claude, Codex, and Bob projections.
- `systematic-debugging/SKILL.md` requires human discussion after three failed fixes. This
  executable gate is present in the Claude and Codex projections; Bob does not deploy the
  skill.
- `receiving-code-review/SKILL.md` stops for clarification when feedback is unclear,
  requests direction when external feedback cannot be verified, stops for human discussion
  when feedback conflicts with prior decisions, and routes architectural escalation to the
  human. These executable gates are present in the Claude and Codex projections; Bob does
  not deploy the skill.
Other audited references are descriptive rather than gates. The two `human partner`
quotes in `test-driven-development/testing-anti-patterns.md`, the source examples and
quoted preferences in `receiving-code-review/SKILL.md`, and the failure-history sentence
in `verification-before-completion/SKILL.md` prescribe no wait or decision. Verification
is deployed to Claude, Codex, and Bob and needs no dispatched adaptation for that sentence.

Lifecycle skills are outside this record's acceptance boundary. In particular,
`using-git-worktrees/SKILL.md` is not silently omitted: its caller-supplied worktree
preference resolves the creation-consent gate, while its baseline-failure gate is tracked
separately by [issue #23][issue-23]. The lifecycle skills' dispatched behavior remains
governed by ADR 0004 rather than this non-lifecycle debt record.

## Why deferred

This change restores attribution and records the governing policy; it does not alter the
runtime instructions of the derived skills. Each executable gate needs a reviewed choice
between resolving from written policy and returning a blocker. Applying one blanket text
substitution would hide those different semantics.

Review by 2026-10-31, one quarter after migration, so the gap is reconsidered on a bounded
cadence even if no upstream refresh occurs. Re-evaluate sooner if an upstream update
touches any named skill or a dispatched run skips or weakens a test because it cannot
obtain human permission.

## Non-regression boundary

This boundary applies to the testing, debugging, review-reception, and verification
skills audited for issue #13; it is not an exhaustive inventory of every vendored skill.
No command or skill may add a new dispatched path to a named executable gate without
asserting the mode and defining whether written policy resolves it or the caller receives
a blocker. A dispatched worker may not treat an absent human as permission to skip or
weaken a test, continue after the debugging stop, guess at unclear or unverifiable review
feedback, or override a prior architectural decision.

## What would resolve it

Audit each named gate against its current callers and choose one sanctioned behavior:

- resolve from explicit issue, plan, and repository testing policy when those inputs fully
  decide the question; or
- return a blocker to the caller when judgment or authority is still required.

Add the result at the gate inside every applicable agent projection, preserve interactive
behavior as the default, and assert dispatched mode at each caller. Resolution requires a
test or transcript proof that each executable gate follows its selected branch, plus a
scoped reference sweep showing every remaining phrase in the four acceptance categories
is descriptive.

## Provenance

target: agents/claude/shared/skills/test-driven-development/SKILL.md
target: agents/codex/shared/skills/test-driven-development/SKILL.md
target: agents/bob/shared/skills/test-driven-development/SKILL.md
target: agents/claude/shared/skills/systematic-debugging/SKILL.md
target: agents/codex/shared/skills/systematic-debugging/SKILL.md
target: agents/claude/shared/skills/receiving-code-review/SKILL.md
target: agents/codex/shared/skills/receiving-code-review/SKILL.md
target: agents/claude/shared/skills/verification-before-completion/SKILL.md
target: agents/codex/shared/skills/verification-before-completion/SKILL.md
target: agents/bob/shared/skills/verification-before-completion/SKILL.md

Migrated for issue #13 from the predecessor repository's debt 0009 at commit
[`dbdcb50f257f098b136adbcc53fc9e48ad4c4159`][predecessor-debt]. The target repository
re-audited every applicable scoped Claude, Codex, and Bob projection on 2026-07-31 rather
than copying the predecessor's Claude-only paths or treating descriptive references as
debt.

[predecessor-debt]: https://github.com/randomparity/claude-config/commit/dbdcb50f
[issue-23]: https://github.com/randomparity/agent-config/issues/23
