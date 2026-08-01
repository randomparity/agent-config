# 0006 — External Scope Authority for Design Workflows

## Status

Accepted (2026-07-31)

## Context

The issue workflow asks for human direction when ambiguity changes a design, but
nested design skills currently classify any curated-skill invocation as unattended.
They may therefore resolve ambiguity internally and review a specification against a
charter derived from that same specification. Issue 17 showed the result: a request for
one canonical skill source grew into transaction, recovery, and persistence guarantees
that the request never authorized.

Review authority is not product-scope authority. A design artifact cannot be the source
that authorizes its own normative guarantees.

## Decision

Freeze scope before design from an external authority: the issue and explicit user
decisions for issue workflows, or the direct user request for standalone design work.
The frozen record states the requested outcome, completion criteria, exclusions,
permitted change surface, unresolved design-changing ambiguities, and provenance.

Track human availability independently from nesting. A nested skill in an interactive
root workflow returns design-changing questions to its caller; a genuinely unattended
workflow parks when such a question lacks prior authority. Downstream skills inherit
that availability rather than inferring it from who invoked them.

Every normative design guarantee must trace to the frozen scope, an explicit later user
decision, or a necessary consequence of either. A consequence is necessary only when no
reasonable implementation can satisfy a frozen completion criterion without it, and the
trace states that reasoning. Contestable necessity is a design-changing ambiguity returned
to the user, not internal authority. Design reviews use the external charter. Permission to
continue reviewing never changes it. An ungrounded guarantee is removed or weakened before
controls are designed for it.

## Consequences

- `WORK:SCOPE` is published before `$design` and carries the frozen charter.
- Interactive nested workflows can still ask the user through their root caller.
- Unattended work may stop for a design-changing ambiguity instead of inventing scope.
- Specs, ADRs, plans, and reviews must expose provenance for normative guarantees.
- Prompt-contract tests guard the ordering, propagation, and provenance rules; they do
  not claim to grade live model behavior.

## Considered & rejected

- **Keep deriving review scope from the reviewed artifact.** The artifact can authorize
  the promise under review, preserving the failure.
- **Add stronger adversarial-review wording only.** More review cannot recover an
  external boundary that was never frozen.
- **Implement a runtime policy engine or live-model grader.** That would duplicate prompt
  policy, add a second mechanism, and exceed the deterministic regression coverage the
  issue requests.
