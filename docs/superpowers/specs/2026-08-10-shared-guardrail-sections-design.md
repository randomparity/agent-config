# Shared guardrail sections across every agent's deployed instructions

Design for issue 88. Decision record: `docs/adr/0041-shared-prose-is-gated-for-copy-identity.md`.

## Problem

Three operating rules live in Claude's deployed instruction file and nowhere else: run
guardrail commands bare so the exit code is the truth, do not run destructive git
commands, and state judgment calls as decisions. Codex and Bob receive neither. Nothing in
the repository detects that, because no gate compares the instruction copies to each
other.

Adding the missing prose to the other copies fixes today's gap and leaves tomorrow's
open. The change is only durable if a gate turns red the next time a rule reaches one copy
and not the rest.

## Outcome

- The three rule sets — CI Verification, Git Safety, Honesty & Decision Framing — are
  present in every deployed instruction file and in the agent-neutral canonical copy.
- `verification-before-completion` treats an untracked file as not-green.
- `just verify` fails when the copies disagree.

## Design

### The shared block

A single Markdown region, delimited by an HTML comment pair, carries all three rule sets:

```markdown
<!-- shared-standards:begin -->
## Guardrails

### CI Verification
...
### Git Safety
...
### Honesty & Decision Framing
...
<!-- shared-standards:end -->
```

`content/instructions/global-development-standards.md` holds the canonical block. Three
deployed files hold byte-identical copies:

| File | Deployed to |
|------|-------------|
| `agents/claude/shared/CLAUDE.md` | Claude's config root |
| `agents/codex/shared/AGENTS.md` | Codex's config root |
| `agents/bob/shared/rules/global-development-standards.md` | Bob's `rules/` directory |

The block is appended as the last section of each file. Placement is not gated; uniform
placement is for the reader.

Block content is agent-neutral — no config path, no invocation syntax, no agent-specific
file name — because byte identity across agents is otherwise unreachable. It also has to
satisfy the deployed-reference rules, since it ships: no bare record number, no bare issue
number, no concrete record path.

### Consolidation, not addition

Two rule clusters already exist in the three long copies and would become duplicates of
the new block. They move into it rather than sitting beside it:

- The `A check's exit code is the truth` paragraph under Workflow moves into CI
  Verification, keeping its zsh `pipestatus` detail.
- The force-push and `git reset --hard` bullet under Commits moves into Git Safety.

Everything else stays where it is. The CLI-tools table row for `trash` / `gio trash` keeps
its own `rm -rf` warning: it is a tool table entry, not a restatement of the rule.

Bob's rules file carries neither cluster today and only gains the block.

### The gate

`scripts/check-shared-standards.sh`, wired into `just verify` through a new
`shared-standards-check` recipe.

Contract, matching `scripts/check-deployed-references.sh`:

- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Repository root derived from `${BASH_SOURCE[0]}/..`; one optional argument overrides it,
  which is how the suite points the checker at a fixture tree.
- `rg` missing, more than one argument, or a subject file missing: exit 2.
- Findings to stderr as `shared-standards: <class>: <file>:<line>`; exit 1.
- Silent success, exit 0.

Finding classes:

| Class | Condition |
|-------|-----------|
| `missing-block` | a subject file has no begin marker |
| `duplicate-block` | a subject file has more than one begin marker or more than one end marker |
| `unterminated-block` | a begin marker with no end marker after it |
| `canonical-shape` | the canonical block carries fewer than three `###` subsections |
| `block-drift` | a deployed block differs from the canonical block by any byte |

`canonical-shape` is the fail-closed guard: without it, emptying the canonical block would
leave the gate green over nothing. It counts subsections and reads none of their text,
which is the line record 0041 draws.

### The untracked-file gate

`content/skills/verification-before-completion/SKILL.md` gains a step in its Gate Function
block, before the claim is made: run `git status --porcelain`, and treat any untracked
file as not-green. A row in the Common Failures table indexes the same rule under the
claim it guards.

## Failure modes

| Mode | Handling |
|------|----------|
| A rule is added to one copy only | `block-drift` names the file and line |
| A copy's block is deleted | `missing-block` names the file |
| A copy's marker is mistyped | `missing-block` or `unterminated-block` names the file |
| The canonical block is emptied to make the gate pass | `canonical-shape` fails |
| The block is duplicated by a bad merge | `duplicate-block` names the file |
| Agent-native prose outside the block differs | passes; that divergence is the point |
| A subject file is renamed or removed | exit 2, not a silent pass |
| Whitespace-only drift | `block-drift`; the comparison is byte-exact |

## Test plan

`scripts/check-shared-standards-test.sh` builds a fixture tree under `mktemp -d
"${TMPDIR:-/tmp}/shared-standards-test.XXXXXX"` with a `trap cleanup EXIT` guarded on that
prefix, so no absolute home path enters a tracked file. `reset_fixture` writes the
canonical file and all three mirrors with a valid, identical block.

Cases, one per row of the failure-mode table plus the baseline:

- baseline fixture passes;
- drift in each of the three mirrors independently — three cases, so a checker that only
  ever compares one mirror cannot pass;
- a mirror whose block is absent; the canonical file whose block is absent;
- duplicated begin marker; begin marker with no end marker;
- canonical block with two subsections;
- trailing-whitespace-only drift;
- divergent prose outside the block passes;
- a removed subject file and a two-argument invocation both exit 2.

The suite is discovered by `just test` from the Git index and needs no recipe edit. Both
new scripts are linted and format-checked the same way. `scripts/list-shell-sources.sh`
gets no edit: its two-space list is closed and these scripts are tab-indented.

## Not in scope

- No renderer or generator for the instruction copies. Record 0001 defers that.
- No change to `agents/bob/shared/AGENTS.md`, whose overlap with Bob's rules file is
  pre-existing.
- No change to `scripts/check-deployed-references.sh` or `scripts/check-carrier-drift.sh`.
- No ADR index; this repository does not keep one.

## Security relevance

Checked against the trigger list: the change adds no entry point an untrusted actor can
reach, touches no authentication, authorization, or tenancy logic, handles no secret,
parses no input it did not produce, builds no command or query from a non-literal value,
widens no permission grant, changes no dependency or pinned action, and alters no file
mode, network exposure, or security-relevant default. The new script reads tracked
Markdown files in the repository it is run against and writes only diagnostics. No threat
model is required.

## Acceptance criteria

1. All three deployed instruction files carry the shared block, and it contains CI
   Verification, Git Safety, and Honesty & Decision Framing.
2. `content/instructions/global-development-standards.md` carries the canonical block.
3. `verification-before-completion`'s Gate Function requires `git status --porcelain` and
   treats an untracked file as not-green.
4. `scripts/check-shared-standards.sh` and its suite exist, match the repository's
   check-script contract, and are reached by `just verify`.
5. Each failure-mode row has a case in the suite, and each case has been observed to fail
   for its own class before the implementation made it pass.
6. `just verify` is green.
