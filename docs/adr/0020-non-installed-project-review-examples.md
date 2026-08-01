# 0020 — Keep project review examples outside global installation

## Status

Accepted (2026-08-01)

## Context

Project-specific review skills need concrete, copyable examples without becoming global
policy. The canonical `content/skills/` inventory is installed for every supported agent,
so placing an Accessibility Reviewer there would make project policy global. Keeping a
real `SKILL.md` elsewhere previously conflicted with the repository rule that reusable
workflow sources live only under `content/skills/`.

## Decision

Allow one narrow second source class under `examples/project-review-skills/`. Packages in
that directory are copyable project-local examples, not globally managed workflows. The
installer must never copy them. The skill-layout guard validates their portable package
shape and reports their inventory separately from canonical skills.

Repository instructions distinguish these examples from reusable global workflow sources.
Each adopting project owns its copied skill and its invocation policy; this repository
does not synchronize or update adopted copies.

## Consequences

Projects get executable examples for Claude Code, Codex, and IBM Bob without expanding
global behavior. The repository owns one additional validated inventory and must keep
installer exclusion tests. Example consumers copy rather than reference the repository,
so later improvements do not propagate automatically.

No other `examples/` subtree may define `SKILL.md`, and agent-native shared trees remain
forbidden from defining skills or commands.

## Considered & rejected

- **Install the example from `content/skills/`.** Rejected because it turns project policy
  into a global workflow for every supported agent.
- **Publish only prose or a non-invocable fragment.** Rejected because issue #31 asks for a
  specific example skill that demonstrates the integration contract.
- **Maintain one native copy per agent.** Rejected because three equivalent sources would
  drift and obscure which example is canonical.
- **Allow arbitrary skill examples anywhere under `examples/`.** Rejected because an
  unbounded exception would recreate multiple workflow-source trees.
