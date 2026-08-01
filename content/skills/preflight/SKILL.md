---
name: preflight
description: "Discover and record a repository's instructions, default branch, working- tree state, guardrail commands, GitHub authentication, decision-record coupling, and parallel-work context before changing code. Use when starting implementation, issue, pull-request, shipping, or campaign work."
---
# Preflight: Discover the Working Environment

Discover and record the repo environment before touching code or switching
branches. Record every finding in the task plan — later steps (`$design`,
`$build-tdd`, `$ship-pr`) depend on `BASE_BRANCH` and the guardrail commands
discovered here. When invoked under `$campaign`, report `BASE_BRANCH` and the
guardrail commands back to the orchestrator, which records them in the campaign
manifest — the orchestrator is the manifest's sole writer, and the manifest
outlives the task plan across a fresh-session resume.

If you are running as part of a larger workflow (e.g. `$work-issue`),
completing preflight means proceed to the next step, not stop. Stop only on a
genuine blocker you have named.

## 1. Read the repo instructions

Read `AGENTS.md`, `AGENTS.md`, and any nested instruction files that apply to
the files you will touch. If those instructions name an installed language
reference for the files' language (Python, TypeScript, Rust, Bash, or GitHub
Actions), read that reference before writing code — it holds the strictness and
supply-chain rules that are no longer inline in `AGENTS.md`.

## 2. Discover the default branch

Store it as `BASE_BRANCH`; do not assume `main`. Prefer
`gh repo view --json defaultBranchRef`, falling back to `git remote show origin`
if needed.

## 3. Inspect the working tree

Run `git status --short --untracked-files=all`. If unrelated local changes
exist, stop and ask the user how to proceed. Do not stash, discard, or
overwrite user work without explicit approval.

## 4. Discover the local guardrail commands

Before the first commit, discover the repo's check suite. Use repo docs, build
manifests, workflow files, and common targets such as `just ci`, `make`,
package scripts, `pyproject.toml`, `Cargo.toml`, or `.github/workflows/`.
Record the exact commands in the task plan. Note which checks CI hard-gates
**individually** vs. only via an aggregate recipe — a guard added to an
umbrella `ci` target may not gate PRs if CI calls the sub-recipes directly.

Where the repo keeps an ADR index, also determine whether a gated check couples
the two — an ADR file requiring a matching index row, or the reverse. Read the
recipe rather than trusting its name; the guard is often a script the recipe
calls. Record a `coupled` / `not coupled` verdict beside the commands, and report
it to the orchestrator under `$campaign`. Step 6, `$design`, and `$campaign`
step 6 all branch on that coupling verdict.

## 5. Confirm gh authentication

Confirm `gh` is authenticated enough to read the issue and later create a PR.
If authentication is missing, stop with the exact command the user should run.

## 6. Detect parallel-run context

If you were dispatched as one of several agents working sibling issues
concurrently, honor what the orchestrator handed you:

- Use the **ADR / migration numbers it assigned**. Do not pick "next free" —
  parallel agents all read the same "next free" and collide on ADR and
  migration filenames. If no number was assigned and you need one, ask the
  orchestrator rather than guessing.
- Stay strictly within the **file scope** you were given; do not edit files
  another agent owns, even to fix an adjacent nit — flag it instead.
- **Leave an ADR index alone** (e.g. target-repository: `docs/adr/README.md`). Write only
  your own ADR file and report `index row pending`; the orchestrator owns the row.
  Rows appended by parallel agents conflict even when their numbers are disjoint,
  because git conflicts on adjacent insertions.
  **Unless CI gates the index** — the gate outranks the run type because the row is a
  merge precondition and this rule is a convention. Take the coupling verdict
  from your dispatch prompt if the orchestrator supplied one, and otherwise run step 4's
  coupling check yourself; only a check CI hard-gates individually counts, not one
  reachable solely through an umbrella recipe. Where such a check enforces "one index row per ADR
  file", withholding the row puts your own stop condition out of reach: the
  check stays red until the row exists, and the orchestrator appends rows only
  after the wave's last PR merges — the merge that check is blocking. Add your own
  single row in your own PR then, matching the length and tone of the rows around
  it, and give its `Status` cell the same value as your record's own `## Status` —
  such a guard usually compares the two. Touch no other row and do not reflow the
  table; the orchestrator's serial-merge rebase (`$campaign` step 6) reconciles the
  adjacent-insertion conflicts between siblings.
- Expect generated-doc and snapshot files to be cross-agent conflict zones; keep
  your edits to them minimal and additive.
