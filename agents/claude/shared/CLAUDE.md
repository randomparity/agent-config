# Global Development Standards

Global instructions for all projects. Project-specific CLAUDE.md files override these defaults.

- Prefer Exa AI (`mcp__exa__web_search_exa`) over `WebSearch` for all web searches
- **Process skills come first.** Before designing, invoke `brainstorming`; before a bug fix,
  `systematic-debugging`; before multi-task implementation, `writing-plans` then
  `subagent-driven-development` (or `executing-plans` without subagents); before claiming
  done, `verification-before-completion`. Invoke them before clarifying questions or
  exploration. A repo-level `Skill` deny or `CLAUDE_CODE_DISABLE_POLICY_SKILLS=1` overrides
  this entirely: do the work directly — don't route to the skill some other way.

## Philosophy

- **No speculative features** - No features, flags, or config nobody needs. Prefer extending an existing entry point over new surface; push back in designs, not just code.
- **No premature abstraction** - No utilities until the third repetition
- **Clarity over cleverness** - Explicit, readable code over dense one-liners
- **Justify new dependencies** - Each is attack surface and maintenance burden
- **No phantom features** - Don't document or reference what isn't implemented and installable. Docs that fail when followed are defects — fix them in the change that exposed the gap.
- **Replace, don't deprecate** - Remove the old path entirely — no shims, dual formats, or migration paths; two mechanisms for one job is a defect surface. Flag dead code.
- **Fix causes, not symptoms** - A workaround is a failure to record (file the issue), not a result. When the plan fights the architecture, propose the deeper change.
- **Generalize the fix** - A defect in one place has siblings: sweep the pattern in the same change and add a guard against recurrence.
- **Verify at every level** - Guardrails (linters, type checkers, hooks, tests) first, not last. Structure-aware tools over text matching. Review your own output critically.
- **Claims are hypotheses** - A reported root cause, review finding, status line, or recalled memory is a lead, not a fact — verify against source or artifact before acting on it.
- **Bias toward action** - Act on anything easily reversed, stating the assumption; a reversible naming/numbering choice is taken and flagged, never blocked on. Ask before committing to interfaces, data models, architecture (including toolchain floors like MSRV), or destructive/external writes. A question is not a task — answer and stop. Surface decisions one or two at a time.
- **Finish the job** - Handle the edge cases you can see, clean up what you touched, flag adjacent breakage — without inventing new scope.

## Code Quality

### Baselines

- ≤100 lines/function, cyclomatic complexity ≤8, 100-char lines; language-specific limits live in the language references below
- Zero warnings from any tool — fix, or inline-ignore with a justification. Check what the gate actually covers: a linter without `--all-targets`/test paths has a blind spot.
- Self-documenting code; no commented-out code; a comment explaining WHAT means refactor instead
- Fail fast with clear, actionable messages (operation, input, suggested fix); never swallow exceptions silently

### Reviewing code

Sync first (`git fetch origin`); evaluate architecture → code quality → tests → performance; cite file:line and recommend a fix.

**A review verdict is input, not a deliverable.** Fix defensible findings in the same turn and re-review. Cap loops at ~5 passes; if findings are mostly consequences of your own earlier fixes, or the count isn't falling, stop and escalate. An exhausted budget without approval is reported as exactly that — never as clean.

### Testing

- **Behavior, not implementation** — if a refactor breaks tests but not code, the tests were wrong
- **Edges and errors, not just the happy path** — every handled error path gets a triggering test
- **Mock boundaries** (slow, non-deterministic, external), **not logic**
- **Verify tests bite:** break the code, watch the test redden, revert. `cargo-mutants`/`mutmut` systematize this; `proptest`/`hypothesis` for parsers, serialization, algorithms
- **A flake that passes on re-run is not evidence** — fix the determinism, not the assertion
- **Test helpers clean up their temp state** (fixtures, not bare mkdtemp)
- **A new test or gate isn't done until its first real run's findings are reported**

### Done means proven

Unit tests green ≠ working. If the environment can exercise the change end-to-end (functional suite, live VM, real hardware, the actual user path), run that proof before reporting done and say which arms ran. Confirm the deployed build matches HEAD before live-testing; detect the host you're on (arch, OS, versions) before building. If your change adds a prerequisite, update provisioning/setup scripts in the same PR — the requirement is yours.

### Blockers

Verify a negative environment claim with the tool the operator actually uses. Enumerate alternate paths (build elsewhere and ship the artifact, another host, a VM) and try the cheapest; when only the operator can fix it, name exactly what you need instead of engineering around it. Never delete a file you didn't create and weren't asked to touch.

## Development

When adding dependencies, CI actions, or tool versions, always look up the current stable version — never assume from memory unless the user provides one.

Never generate code on main/master — ensure a branch first, prompting the user if needed.

**Analysis is not implementation.** An audit, review, or "look into X" produces findings in the response — no file writes, no mutating commands, until asked to fix. Audit report files are staging artifacts: convert to issues, then delete them. In a black-box evaluation, prior memories and out-of-scope source are contamination — don't recall, don't record.

**Findings become issues.** Deferred work, skipped criteria, and adjacent breakage get `gh issue create` in the same turn — a finding that lives only in your report may never be read. Size each issue to one PR; a large finding becomes an epic with PR-sized sub-issues, labeled from the repo's existing labels.

**`gh` output hygiene:** always pass `--json <explicit-fields>` on `gh issue view` / `gh pr view` / `gh ... list` (plus `--limit N` on lists) — default output includes full bodies and all comments. Fetch `comments` only when a step needs the discussion; prefer server-side `--search`/`--label`/`--state` filters.

### CLI tools

| tool | replaces | usage |
|------|----------|-------|
| `rg` (ripgrep) | grep | recursive by default; **`-r` is `--replace`, not recursive** — use `rg -n` / `rg -ln` |
| `fd` | find | `fd "*.py"` (Debian ships it as `fdfind`) |
| `ast-grep` | - | `--pattern '$FUNC($$$)' --lang py` — prefer over rg for code structure |
| `shellcheck` / `shfmt` | - | shell lint / format (`shfmt -i 2 -w`) |
| `actionlint` | - | Actions linter; auto-discovers workflows (a directory arg errors) |
| `zizmor` | - | `zizmor .github/workflows/` — Actions security audit |
| `prek` | pre-commit | `prek run` — fast git hooks (Rust, no Python) |
| `trash` (mac) / `gio trash` (Linux) | rm | recoverable delete. **Never use `rm -rf`** |

### On-demand references

Read the matching reference BEFORE the work it covers:

- **Python** — `~/.claude/languages/python.md`
- **Node/TypeScript** — `~/.claude/languages/typescript.md`
- **Rust** — `~/.claude/languages/rust.md`
- **Bash** — `~/.claude/languages/bash.md`
- **GitHub Actions** — `~/.claude/languages/github-actions.md`
- **Dispatching subagents / parallel fan-outs** — `~/.claude/references/orchestration.md` (worktree placement, fan-out caps, report contract, limit specs)

## Workflow

**Before committing:** re-read the diff for complexity and naming; run relevant tests (not the full suite) and linters — all green first. Commit after each fix and each review round; review-driven changes get their own commit, not a batch at the end.

**Commits:**
- Conventional commits 1.0.0, imperative mood, ≤72-char subject, one logical change per commit
- Never amend/rebase pushed commits; never push directly to main; never commit secrets (use gitignored `.env`). Plans are transient — don't commit them; specs and ADRs are the durable record.
- **Never squash-merge code PRs** — per-commit history is load-bearing for `git bisect`; use `--rebase` or `--merge`. Squash only collapses review iterations on non-code artifacts. An explicit user instruction settles it either way.
- All force pushes (`--force` **and** `--force-with-lease`) and `git reset --hard` are denied by settings policy. Recover with `git restore`/`git stash`/`git revert`; a truly-needed force push is the user's to run. Never bundle a possibly-denied command into an `&&` chain.
- Non-default SSH identities: pin the key — `ssh -i <key> -o IdentitiesOnly=yes`
- Install prek in every repo (`prek install`); hooks and CI invoke the project's guardrail recipe (`just ...`/`make ...`), never re-typed command strings — duplicated command text is how gates silently drift

**Merged means clean.** When a PR merges: checkout main, pull, delete the local and remote-tracking branch, prune, remove the worktree, account for anything still modified — unprompted, same turn.

**Waiting on something long** (build, CI, dispatched agent): start one background task and read it when it completes. No foreground `sleep`, no polling manufactured to look busy — do other work or say plainly what you're blocked on and for roughly how long.

**Pull requests:** describe what the diff does now — not discarded approaches or prior iterations. Plain, factual language; avoid: critical, crucial, essential, significant, comprehensive, robust, elegant.

**CI green ≠ mergeable ≠ done.** CI runs on the branch head, not the merge result: poll `gh pr view <n> --json mergeable,mergeStateStatus` alongside `gh pr checks <n> --json name,state` (compact snapshots on a backing-off interval, never `--watch`); exit only on checks green **and** state `CLEAN`/`MERGEABLE`. Otherwise stop polling and act — rebase, resolve, re-run guardrails, re-push; after one failed attempt, surface it rather than spinning. Green + mergeable is necessary, not sufficient: an independent adversarial review precedes merge.

**A check's exit code is the truth.** Run gates BARE — no `| tail`/`| head`, no `>/dev/null`, no `|| true`; a pipeline returns the *last* command's exit code and hides the real failure. If you must capture output, `set -o pipefail`; these hosts run zsh, where `${PIPESTATUS[0]}` reads as empty (the array is `pipestatus`, 1-indexed). Regenerate generated artifacts *before* the check runs.

**Before a long, expensive, or remote operation:** confirm the scope actually asked for (quick verify vs. full run — don't assume the bigger one) and that the target host meets requirements (OS, arch, versions). Don't re-run a full suite for a doc-only change.
