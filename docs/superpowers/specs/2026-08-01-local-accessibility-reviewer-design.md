# Local Accessibility Reviewer Design

## Scope authority

- Interaction: interactive.
- Scope identity: <https://github.com/randomparity/agent-config/issues/31> plus
  `7e025cfa-3d63-41f2-a6df-99a8a6a32581`.
- Outcome: document project-local review-skill integration and provide an Accessibility
  Reviewer example.
- Completion criteria: explain integration requirements; provide a copyable project-local
  Accessibility Reviewer; keep it outside global installation; pass repository verification.
- Provenance: issue #31, the operator's 2026-08-01 example selection, repository
  instructions, and the necessary local/global separation.
- Exclusions: no globally installed Accessibility Reviewer, no change to `review-loop`,
  and no additional example-skill inventories.
- Surface: `examples/project-review-skills/`, directly related README and AGENTS policy,
  migration of the existing Bob `project-context` example, ADR 0020, and verification
  needed to prove local placement and global-install exclusion.
- Ambiguities: none.

## Context

The repository installs every package under `content/skills/` globally for Claude Code,
Codex, and IBM Bob. Issue #31 asks for a different lifecycle: a review skill owned by an
individual project because its checks depend on that project's product requirements. The
example must teach both the skill contract and how project instructions insert the review
into the existing workflow without making a project-specific policy global.

[ADR 0020](../../adr/0020-non-installed-project-review-examples.md) records the operator's
decision to allow one separately validated, non-installed example inventory. Repository
instructions must name this exception rather than claiming every real `SKILL.md` belongs
under the globally installed tree.

Move `examples/bob-project/.bob/skills/project-context/SKILL.md` into
`examples/project-review-skills/project-context/SKILL.md`. Normalize only its description
from commit `f05038fbaa58f34b55f65c7902cb92628e653e53` to exactly
`description: "Load project-specific context from public project files."`; every other
byte, including delimiters and newlines, stays equal to that commit's
`examples/bob-project/.bob/skills/project-context/SKILL.md` blob. Update Bob guidance to
copy the package from the canonical example inventory; do not retain a shim or duplicate
source.

The selected example is an Accessibility Reviewer. It reviews user-interface changes
against the target project's declared accessibility requirements. When the project does
not declare a baseline, the reviewer stops and asks the project owner to supply one rather
than silently selecting policy. It does not replace automated accessibility tests or the
existing adversarial and security review stages.

## Considered approaches

### Recommended: one neutral example package plus placement instructions

Keep one source at `examples/project-review-skills/accessibility-reviewer/SKILL.md` and
document the native project-local destination for each supported agent. A project copies
the package it needs and adds an invocation rule to its project instructions. This keeps
the example readable, prevents three copies from drifting, and makes global exclusion
visible in the repository layout.

### Rejected: install the reviewer globally

Adding the package to `content/skills/` would make it available everywhere, contradicting
the issue's distinction between project policy and global review behavior.

### Rejected: maintain one native example per agent

Three equivalent copies below separate example projects would demonstrate placement but
create immediate drift. The repository's canonical-source architecture favors one neutral
source with agent-specific destination documentation.

## Repository changes

### Example package

Create `examples/project-review-skills/accessibility-reviewer/SKILL.md` with portable
four-line frontmatter and a read-only review workflow. The reviewer:

1. resolves the user-supplied files or base branch, records the normalized target, and
   uses the same target as the preceding branch review;
2. reads the target project's accessibility policy and relevant UI or design-system
   conventions;
3. examines semantics, keyboard operation, focus behavior, names and labels, contrast and
   non-color cues, zoom/reflow, motion, status announcements, and validation errors when
   those concerns are present in the target;
4. distinguishes source evidence from items that require browser, assistive-technology,
   or human verification;
5. reports one of `approve`, `needs-attention`, `needs-manual-check`, or `not-applicable`,
   plus prioritized findings with evidence, user impact, applicable requirement, and a
   concrete remediation; and
6. remains read-only unless a caller separately asks for fixes.

The skill applies only requirements named by the project policy; it never selects an
additional accessibility standard. It must not claim conformance from source inspection
alone. Verdict precedence is deterministic: any source finding returns `needs-attention`;
otherwise any outstanding runtime or human verification returns `needs-manual-check`;
otherwise an applicable review returns `approve`. `not-applicable` reports the normalized
inspected target. The caller applies the target project's shipping policy to manual checks.
Empty or unresolvable targets produce an actionable error instead of silently reviewing
unrelated files.

### Integration documentation

Add a README section explaining that local review skills live in the target project, not
this repository's global installation. Document these destinations:

- Claude Code: `.claude/skills/accessibility-reviewer/`
- Codex: `.agents/skills/accessibility-reviewer/`
- IBM Bob: `.bob/skills/accessibility-reviewer/`

Show a short project-instruction snippet that invokes the local reviewer with the same
base or file target as the normal branch review for UI-affecting changes, requires
disposition of defensible findings, and reruns the reviewer after behavioral fixes. List
the exact package destinations, including `accessibility-reviewer/`. State that projects
should select only the reviewers their own requirements justify.

### Verification

Extend the existing skill-layout guard rather than creating a separate checker. Validate
the example with the same portable name, frontmatter, UTF-8, regular-file, no-symlink, and
portable-path rules used for globally installed skills. Keep its root separate from the
global inventory count.

Extend the layout guard's fixture suite with a valid project-review example and a failure
case proving malformed example frontmatter is rejected. Extend installer coverage to
assert that the local example is absent from every global destination after an all-agent
install. Add a fixture proving `SKILL.md` anywhere else below `examples/` is rejected, so
ADR 0020's exception cannot widen silently.

## Failure behavior and edge cases

- Missing target-project accessibility policy: stop and request a declared baseline; the
  example does not choose product policy for its adopter.
- Non-UI change: return `not-applicable` with the inspected target rather than inventing
  findings.
- Evidence requiring runtime inspection: return `needs-manual-check`, identify the check
  and expected evidence, and leave the shipping decision to project instructions.
- Unresolvable review target: stop with the unresolved input and suggested valid forms.
- Unsupported agent placement: the example remains ordinary Agent Skills content; the
  documentation promises only the three repository-supported destinations.
- Mixed source findings and manual checks: return `needs-attention`; report the manual
  checks alongside findings so they are not lost.
- Global install regression: installer and layout tests fail if the example is copied into
  the globally managed skill tree or destination.
- Legacy Bob source: the old `.bob/skills/project-context/SKILL.md` path is absent and the
  canonical package differs only by the authorized description quoting.

## Acceptance tests

- `scripts/check-skill-layout-test.sh` proves a valid example passes and malformed
  project-review frontmatter fails, and rejects `SKILL.md` in every other `examples/`
  subtree. It also asserts the legacy Bob skill path is absent and Bob guidance names
  `examples/project-review-skills/project-context/` as the source and
  `.bob/skills/project-context/` as the destination.
- Before committing the move, read the exact source commit and path above, replace only
  line 3 with the exact approved description, then compare the complete normalized result
  byte-for-byte with `examples/project-review-skills/project-context/SKILL.md`.
- `install-test.sh` proves all three installed global skill trees exclude
  `accessibility-reviewer` and `project-context`.
- `just verify` passes, including shell lint, formatting, skill layout, installation,
  public-safety, deployed-reference, and Actions checks.

## Durable execution context

- Branch: `feat/accessibility-reviewer-31`
- Base branch: `main`
- Local guardrail: `just verify`
- CI guardrail: `just ci` (`just verify` plus `prek run --all-files`)
- ADR/index coupling: not coupled; ADR 0020 is added and root records use the directory
  listing as their index, so no hand-maintained index row is required.
