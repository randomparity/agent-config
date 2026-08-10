# Subagent orchestration

On-demand reference for agent instruction files — read before dispatching any
subagent or parallel fan-out.

## Worktrees

Each parallel subagent works in its own worktree — never a shared working directory. Worktrees live OUTSIDE the repository tree (sibling root like `../<repo>-worktrees/<branch>`), never nested inside it: a nested worktree gets walked by whole-tree tooling (prek/ruff/ty, test discovery, search), which then lints other agents' in-flight code and fails commits for errors that aren't yours. When the harness's built-in worktree isolation would place the worktree inside the repo, don't use it — have the agent `git worktree add` an external path and `cd` there as its first step.

## Fan-out discipline

- Cap fan-outs at ~4–5 concurrent agents; state the planned count and its derivation before dispatching
- Never give two agents overlapping file scopes, and keep them out of shared index/registry files (ADR indexes, command enums, migration counters) — pre-assign record numbers and file scopes up front; collisions cost O(N²) conflict resolutions
- Baseline pre-existing failures once (e.g. via `git stash` on a clean run) and hand the list to every agent rather than letting each rediscover them
- Before dispatching, re-read the completion reports already in hand — re-assigning finished work costs a whole agent run
- Before acting on a queued observation about another agent's PR, re-read live state (`gh pr view --json state,mergeable`) — cross-agent messages go stale
- A silent agent is not a dead one — dispatched agents run in the background and answer while they work, so a direct message is a non-destructive liveness probe and a reply of any content proves it alive. Nothing weaker does: an idle branch, an unchanged file, an unanswered expectation are all consistent with a design phase or a CI wait

## Report contract

Every dispatched subagent ends its run with a condensed report — the parent pays for every returned token, so cap it at ~1–2k tokens and return **references, not content**:

- outcome (done / blocked / needs-decision), one line
- branch and PR ref, if any
- files touched — paths only
- guardrail status — which checks ran, pass/fail
- blockers and decisions the parent must act on
- artifact paths (specs, plans, findings, review files) — never their bodies

Concretely: no quoted file content or diffs, no per-finding tables, no enumerating test names or new files — paths and counts only — and omit any section you'd leave empty. A dispatcher may replace or extend these fields with a task-appropriate set (e.g. a read-only triage returns verdict/evidence/rationale); the cap and the references-only rule always hold.

## Limits handed to agents

For any limit you hand an agent, state all five: unit, reference clock, scope (per-request vs per-flow), consequence of violation, and recovery action.
