# 0005 — CHARTER label agreement is ungated

## Status

Open
review-by: 2026-11-01

## Concern

`content/skills/challenge/SKILL.md` stops target classification at the first line whose
first content token is `CHARTER`. `content/skills/review-loop/SKILL.md` emits its trailing
scope block behind that literal. Their agreement is only partly gated.
`scripts/check-workflow-scope-contract-test.sh` requires review-loop's carrier to begin
with the exact `CHARTER` label, but it does not assert that challenge still recognizes
that label as its parsing boundary. A one-sided change to challenge can therefore leave
the emitter check green while charter content becomes review targets or silently narrows
the intended target list.

This applies to the canonical challenge/review-loop pair installed for Claude and Codex,
including each client's native skill invocation. IBM Bob is excluded until its native
transport of the line-oriented argument block is covered by the same proof. Threat-scan
consumes challenge's parsing rules but does not emit the review-loop block, so it is not the
second owner of this two-file agreement.

## Why deferred

Extending the existing scope-contract gate is small, but the check must prove both sides
without coupling itself to incidental prose. Native invocation fixtures must also establish
whether the source-level agreement survives transport. Issue #11 owns records only and
cannot expand that executable gate.

The 2026-11-01 review date is three months after adoption. It gives the repository one
quarter to complete the existing gate without leaving the consumer side of the parsing
boundary untested on an indefinite schedule.

## Non-regression boundary

The existing scope-contract test must continue to require review-loop's exact carrier
label. Any change to challenge's stop rule must review the pair together and preserve the
same case-sensitive `CHARTER` literal. Review-loop must keep real target tokens before the
block and challenge must error when the boundary leaves no target. Its preference for
component names rather than paths remains mitigation, not proof. A one-sided label edit
makes this debt blocking.

## What would resolve it

Extend the `just verify` scope-contract guardrail to bind challenge's recognized stop label
to review-loop's already-checked carrier label. It must fail when either workflow changes
its side alone or places the block where the parser will not recognize it, and it must
exercise the Claude and Codex native projection/invocation fixtures. Resolution requires
separate negative mutations of the emitter and consumer proving that either one-sided
rename turns the guardrail red.

## Provenance

target: content/skills/challenge/SKILL.md
target: content/skills/review-loop/SKILL.md

Migrated for issue #11 from the predecessor repository's [debt 0008][predecessor] on
2026-08-01. The predecessor's paths, issue numbers, and ADR numbers remain provenance only;
current ownership is established by these target paths and issue #11.

[predecessor]: https://github.com/randomparity/claude-config/blob/main/docs/debt/0008-charter-label-agreement-is-ungated.md
