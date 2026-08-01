# Local Accessibility Reviewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document project-local review-skill integration and provide a validated,
copyable Accessibility Reviewer example that is never globally installed.

**Architecture:** ADR 0020 authorizes one non-installed example inventory at
`examples/project-review-skills/`. The skill-layout guard validates that inventory with
the same portable package rules as global skills and rejects `SKILL.md` elsewhere under
`examples/`, while the installer continues to copy only `content/skills/`.

**Tech Stack:** Bash, Agent Skills Markdown/YAML frontmatter, repository shell fixtures,
`just` guardrails.

## Global Constraints

- Branch: `feat/accessibility-reviewer-31`; base: `main`.
- Keep the example outside `content/skills/` and every `agents/*/shared/` tree.
- Permit project-review example `SKILL.md` files only under
  `examples/project-review-skills/`, as recorded by ADR 0020.
- Do not change `review-loop` behavior or add dependencies.
- The reviewer is read-only unless a caller separately requests fixes.
- The reviewer never returns `approve` while a manual check remains unresolved.
- Missing project accessibility policy stops review instead of selecting a fallback.
- Apply only requirements named by project policy and read relevant UI conventions.
- Use deterministic verdict precedence: source findings, then manual checks, then approve.
- Record the normalized target in every verdict and use the preceding branch-review target.
- Run `just verify` before every commit; CI runs `just ci`.
- Rollback is `git revert` of the task's commit; no external state is created.

---

### Task 1: Add and validate the project-local review example

**Files:**

- Modify: `scripts/check-skill-layout-test.sh`
- Modify: `scripts/check-skill-layout.sh`
- Create: `examples/project-review-skills/accessibility-reviewer/SKILL.md`

**Interfaces:**

- Consumes: the existing portable path, package name, frontmatter, UTF-8, regular-file,
  no-symlink, and reserved-name validation rules.
- Produces: the Accessibility Reviewer package and validation of direct packages under
  `examples/project-review-skills/`, reported separately from the canonical global skill
  count.

- [ ] **Step 1: Add a valid local-example fixture and a failing frontmatter case**

Add an inventory-aware fixture helper that writes a named `SKILL.md` beneath either
`content/skills/` or `examples/project-review-skills/`. Seed `accessibility-reviewer` in
every fixture. Update the real-repository and two-skill expected summaries to include one
project-review example.

Convert the existing package-validation cases into a small test matrix that runs each case
once against the canonical inventory and once against the project-review inventory. The
matrix must cover malformed frontmatter, name mismatch, empty description, empty body,
reserved package names, internal symlinks, non-regular entries, non-portable paths,
case-fold collisions, and invalid UTF-8. Preserve the canonical-only installed-config-root
case because local project documentation may legitimately use native project paths.

Add local-inventory cases for a missing `examples/project-review-skills/` root and a
non-directory child directly beneath it. These prove inventory discovery separately from
the shared package validators.

For the malformed frontmatter case, expect:

```text
examples/project-review-skills/accessibility-reviewer/SKILL.md: description must be a one-line JSON string
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: FAIL because the current checker ignores project-review examples and its summary
omits the new inventory.

- [ ] **Step 3: Write the example skill**

Create four-line frontmatter with `name: accessibility-reviewer` and a description that
triggers for accessibility review of UI changes. Implement sections for target resolution,
required project-policy discovery, applicability, source review categories, manual-check
classification, the four verdicts, finding fields, and read-only constraints. State that
an unresolved target or missing policy stops with an actionable error.

- [ ] **Step 4: Generalize the existing validator only as far as the second inventory**

Change path reporting to derive paths relative to the repository. Add a function that
requires `examples/project-review-skills/`, validates each direct child with the existing
package rules, counts it separately, and rejects non-directory children. Keep the global
config-root scan scoped to installed `content/skills/`. Emit:

```text
skills-check: ok (<N> canonical skills, <M> project review examples)
```

- [ ] **Step 5: Run focused tests and repository guardrails**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: PASS with every shared package case reported for both inventories and the two
local-inventory discovery cases reported once.

Run: `just verify`

Expected: PASS with zero warnings.

- [ ] **Step 6: Commit the example and structural guard**

```bash
git add examples/project-review-skills/accessibility-reviewer/SKILL.md scripts/check-skill-layout.sh scripts/check-skill-layout-test.sh
git commit -m "feat: add local accessibility reviewer example"
```

### Task 2: Document integration and prove global exclusion

**Files:**

- Modify: `README.md`
- Modify: `install-test.sh`

**Interfaces:**

- Consumes: project-supplied review targets and a declared project accessibility policy.
- Produces: `approve`, `needs-attention`, `needs-manual-check`, or `not-applicable`, with
  evidence-backed findings where relevant.

- [ ] **Step 1: Add failing global-exclusion assertions**

After each installed destination's canonical-skill assertion, add:

```bash
assert_not_file "$DESTINATION/skills/accessibility-reviewer/SKILL.md"
```

using the existing Claude, Codex, and Bob destination variables.

- [ ] **Step 2: Run the focused installer test and confirm the proof is meaningful**

Run: `./install-test.sh`

Expected: PASS because the current installer already excludes `examples/`. Temporarily
point one assertion at an existing global skill, confirm it fails with `expected path to be
absent`, then restore the assertion before continuing. This is a test-sensitivity check,
not a committed mutation.

- [ ] **Step 3: Document local placement and workflow integration**

Add a `Project-local review skills` README section. Explain why these examples are not
globally installed, list the Claude `.claude/skills/`, Codex `.agents/skills/`, and Bob
`.bob/skills/` destinations, and show a project instruction that invokes the reviewer
after normal branch review for UI-affecting changes, dispositions defensible findings,
reruns after behavioral fixes, and treats unresolved manual checks according to project
policy.

- [ ] **Step 4: Run focused and full verification**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: PASS and report one project review example.

Run: `./install-test.sh`

Expected: PASS and prove the example is absent from all three global destinations.

Run: `just verify`

Expected: PASS with zero warnings.

- [ ] **Step 5: Commit the integration documentation and proof**

```bash
git add README.md install-test.sh
git commit -m "docs: explain local review skill integration"
```

### Task 3: Enforce the authorized boundary and finish the review contract

**Files:**

- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `examples/project-review-skills/accessibility-reviewer/SKILL.md`
- Create: `examples/project-review-skills/project-context/SKILL.md`
- Delete: `examples/bob-project/.bob/skills/project-context/SKILL.md`
- Modify: `scripts/check-skill-layout.sh`
- Modify: `scripts/check-skill-layout-test.sh`
- Modify: `install-test.sh`

**Interfaces:**

- Consumes: ADR 0020, the project accessibility policy, relevant UI conventions, and the
  exact base or file target used by the preceding branch review.
- Produces: one normalized inspected target and exactly one verdict with precedence
  `needs-attention` → `needs-manual-check` → `approve`; `not-applicable` also names the
  target.

- [ ] **Step 1: Add failing boundary and reviewer-contract tests**

Add a fixture at `examples/other/SKILL.md` and expect the skill-layout check to fail with:

```text
examples/other/SKILL.md: SKILL.md is allowed only under examples/project-review-skills
```

Extend the existing example-content assertions to require these exact behavioral clauses:

```text
Any source finding takes precedence over outstanding manual checks: return `needs-attention`.
Apply only accessibility requirements named by the project policy.
Record the normalized inspected target in every verdict.
When target resolution fails, report the raw unresolved input.
Also report the accepted base-branch or explicit-file-list forms.
Create the normalized inspected target only after resolution succeeds.
Use the same base branch or explicit file list as the preceding branch review.
Keep outstanding manual checks in the report when source findings return `needs-attention`.
Copy `project-context` from `examples/project-review-skills/project-context/` to `.bob/skills/project-context/`.
```

Run: `bash scripts/check-skill-layout-test.sh`

Expected: FAIL because the checker permits another `examples/` skill and the example lacks
the seven contract clauses.

- [ ] **Step 2: Enforce ADR 0020's single example inventory**

Before validating the authorized inventory, scan regular or symlinked files named
`SKILL.md` below `examples/`. Reject every match outside
`examples/project-review-skills/<package>/SKILL.md` with the exact diagnostic above. Do
not reject ordinary example Markdown or agent-native files that are not named `SKILL.md`.

Move the tracked Bob `project-context` package to
`examples/project-review-skills/project-context/SKILL.md`. Change only line 3 to
`description: "Load project-specific context from public project files."`; preserve every
other byte.
Delete the old source path; do not leave a shim. Add installer absence assertions for
`project-context/SKILL.md` beside the Accessibility Reviewer assertions for all agents.
Add focused assertions that the old path is absent and Bob guidance contains the exact
source and destination clause above. Before commit, run:

```bash
(
  migration_tmp=$(mktemp -d "${TMPDIR:-/tmp}/project-context-migration.XXXXXX")
  trap 'rm -R "$migration_tmp"' EXIT
  git show f05038fbaa58f34b55f65c7902cb92628e653e53:examples/bob-project/.bob/skills/project-context/SKILL.md > "$migration_tmp/project-context.base"
  sed '3s/.*/description: "Load project-specific context from public project files."/' \
    "$migration_tmp/project-context.base" > "$migration_tmp/project-context.normalized"
  cmp "$migration_tmp/project-context.normalized" examples/project-review-skills/project-context/SKILL.md
)
```

Expected: `cmp` exits 0 with no output.

- [ ] **Step 3: Complete the Accessibility Reviewer contract**

Require the caller to supply the same base branch or explicit file list used by the
preceding branch review. After successful resolution, normalize and report that target in
all four verdicts. On resolution failure, report the raw unresolved input and accepted
base-branch or explicit-file-list forms without creating a normalized inspected target.
Read the project's declared accessibility policy plus relevant UI or design-system
conventions. Apply only requirements named by that policy. Define mixed-result precedence:
source findings return `needs-attention` while manual checks remain listed; only manual
checks return `needs-manual-check`; neither returns `approve`.

- [ ] **Step 4: Align repository and integration documentation**

Update `AGENTS.md` to state that reusable installed workflow sources live only under
`content/skills/`, with ADR 0020's sole non-installed, copyable exception under
`examples/project-review-skills/`. Preserve the prohibition on agent-native skill and
command sources.

Update README destinations to the exact package paths:

```text
.claude/skills/accessibility-reviewer/
.agents/skills/accessibility-reviewer/
.bob/skills/accessibility-reviewer/
```

Update the sample instruction to pass the same base or explicit file list used by the
preceding branch review.

Update Bob example guidance to copy `project-context` from
`examples/project-review-skills/`; remove claims that the Bob tree owns a skill source.

- [ ] **Step 5: Run focused and full verification**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: PASS, including the unauthorized-example failure and reviewer-contract checks.

Run: `./install-test.sh`

Expected: PASS; both project-review examples remain absent from all global destinations.

Run: `just verify`

Expected: PASS with zero warnings.

- [ ] **Step 6: Commit the bounded review integration**

```bash
git add AGENTS.md README.md install-test.sh examples/bob-project/.bob/skills/project-context/SKILL.md examples/project-review-skills/accessibility-reviewer/SKILL.md examples/project-review-skills/project-context/SKILL.md scripts/check-skill-layout.sh scripts/check-skill-layout-test.sh
git commit -m "fix: bound project review skill examples"
```

## Self-review

- Every spec requirement maps to Task 1, Task 2, or Task 3.
- No placeholder steps or unresolved signatures remain.
- The checker extension precedes the example it validates.
- Focused checks run before the full guardrail in each task.
- Branch, base, guardrails, exclusions, rollback, and review semantics are durable here.
