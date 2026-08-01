# Local Accessibility Reviewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document project-local review-skill integration and provide a validated,
copyable Accessibility Reviewer example that is never globally installed.

**Architecture:** Keep local examples in a separate `examples/project-review-skills/`
inventory. Extend the existing skill-layout guard to validate that inventory with the same
portable package rules as global skills, while the installer continues to copy only
`content/skills/`.

**Tech Stack:** Bash, Agent Skills Markdown/YAML frontmatter, repository shell fixtures,
`just` guardrails.

## Global Constraints

- Branch: `feat/accessibility-reviewer-31`; base: `main`.
- Keep the example outside `content/skills/` and every `agents/*/shared/` tree.
- Do not change `review-loop` behavior or add dependencies.
- The reviewer is read-only unless a caller separately requests fixes.
- The reviewer never returns `approve` while a manual check remains unresolved.
- Missing project accessibility policy stops review instead of selecting a fallback.
- Run `just verify` before every commit; CI runs `just ci`.
- Rollback is `git revert` of the task's commit; no external state is created.

---

### Task 1: Validate project-local review examples

**Files:**

- Modify: `scripts/check-skill-layout-test.sh`
- Modify: `scripts/check-skill-layout.sh`

**Interfaces:**

- Consumes: the existing portable path, package name, frontmatter, UTF-8, regular-file,
  no-symlink, and reserved-name validation rules.
- Produces: validation of direct packages under `examples/project-review-skills/`, reported
  separately from the canonical global skill count.

- [ ] **Step 1: Add a valid local-example fixture and a failing frontmatter case**

Add a `write_project_review_skill` fixture helper that writes
`examples/project-review-skills/<name>/SKILL.md`. Seed `accessibility-reviewer` in every
fixture. Update the real-repository and two-skill expected summaries to include one
project-review example. Add a case whose example uses `summary:` instead of `description:`
and expect:

```text
examples/project-review-skills/accessibility-reviewer/SKILL.md: description must be a one-line JSON string
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: FAIL because the current checker ignores malformed project-review examples or
because its summary omits the new inventory.

- [ ] **Step 3: Generalize the existing validator only as far as the second inventory**

Change path reporting to derive paths relative to the repository. Add a function that
requires `examples/project-review-skills/`, validates each direct child with the existing
package rules, counts it separately, and rejects non-directory children. Keep the global
config-root scan scoped to installed `content/skills/`. Emit:

```text
skills-check: ok (<N> canonical skills, <M> project review examples)
```

- [ ] **Step 4: Run focused tests and repository guardrails**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: PASS with the focused-failure count incremented by one.

Run: `just verify`

Expected: PASS with zero warnings.

- [ ] **Step 5: Commit the structural guard**

```bash
git add scripts/check-skill-layout.sh scripts/check-skill-layout-test.sh
git commit -m "test: validate local review skill examples"
```

### Task 2: Add and document the Accessibility Reviewer

**Files:**

- Create: `examples/project-review-skills/accessibility-reviewer/SKILL.md`
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

- [ ] **Step 3: Write the example skill**

Create four-line frontmatter with `name: accessibility-reviewer` and a description that
triggers for accessibility review of UI changes. Implement sections for target resolution,
required project-policy discovery, applicability, source review categories, manual-check
classification, the four verdicts, finding fields, and read-only constraints. State that
an unresolved target or missing policy stops with an actionable error.

- [ ] **Step 4: Document local placement and workflow integration**

Add a `Project-local review skills` README section. Explain why these examples are not
globally installed, list the Claude `.claude/skills/`, Codex `.agents/skills/`, and Bob
`.bob/skills/` destinations, and show a project instruction that invokes the reviewer
after normal branch review for UI-affecting changes, dispositions defensible findings,
reruns after behavioral fixes, and treats unresolved manual checks according to project
policy.

- [ ] **Step 5: Run focused and full verification**

Run: `bash scripts/check-skill-layout-test.sh`

Expected: PASS and report one project review example.

Run: `./install-test.sh`

Expected: PASS and prove the example is absent from all three global destinations.

Run: `just verify`

Expected: PASS with zero warnings.

- [ ] **Step 6: Commit the example and documentation**

```bash
git add README.md install-test.sh examples/project-review-skills/accessibility-reviewer/SKILL.md
git commit -m "feat: add local accessibility reviewer example"
```

## Self-review

- Every spec requirement maps to Task 1 or Task 2.
- No placeholder steps or unresolved signatures remain.
- The checker extension precedes the example it validates.
- Focused checks run before the full guardrail in each task.
- Branch, base, guardrails, exclusions, rollback, and review semantics are durable here.
