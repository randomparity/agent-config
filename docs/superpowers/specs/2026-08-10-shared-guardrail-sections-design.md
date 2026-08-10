# Shared guardrail sections across every agent's deployed instructions

Design for issue 88. Decision record: `docs/adr/0041-shared-prose-is-gated-for-copy-identity.md`.

## Problem

The operating rules this change generalizes are spread unevenly across the copies of the
global development standards. Exit-code truth, the destructive-git ban, the `trash` row's
deletion warning, and the decision-framing rules are in Claude's file, Codex's file and the
canonical copy, and in neither Bob file. The `git clean -fd` and `rm -f` bans are in none
of them.

Nothing in the repository detects the unevenness: no gate compares an instruction copy to
another copy or to the canonical one. Adding the missing prose fixes today's gap and
leaves tomorrow's open. The change is only durable if a gate turns red the next time a
rule reaches one copy and not the rest.

### What the block adds

The gate deliberately asserts nothing about the block's content, so every rule the block
states that is not already in the four copies is listed here with its source. A reviewer
checking criterion 1 has this list and nothing else; a rule not on it and not in the
consolidation table below is scope this design did not authorize.

| New rule | Source |
|----------|--------|
| Before claiming green, done, or mergeable, run `git status --porcelain`; any untracked file means not green | issue 88, Expected bullet 3 and Proposed approach |
| Never pipe a guardrail command into `grep` (the existing rule names `tail`, `head`, `>/dev/null`, `\|\| true`) | issue 88, Proposed approach |
| Never run `git clean -fd` or `rm -f` | issue 88, Proposed approach |
| Verify a historical claim about a repository with `git log` or `gh` and cite the output | issue 88, Proposed approach |
| State a judgment call as a decision with its rationale rather than handing the choice back | issue 88, Proposed approach |
| Do authorized follow-up work rather than offering it back | issue 88, Proposed approach |

Everything else in the block is one of the six existing rules the consolidation table
moves, reworded only to drop agent-specific detail.

## Outcome

- The three rule sets — CI Verification, Git Safety, Honesty & Decision Framing — are
  present in every deployed instruction file and in the agent-neutral canonical copy.
- `verification-before-completion` treats an untracked file as not-green.
- `just verify` fails when the copies disagree.

## Design

### The shared block

`content/instructions/global-development-standards.md` holds the canonical block, appended
as the file's last section. Three deployed files hold byte-identical copies, appended the
same way:

| File | Deployed to |
|------|-------------|
| `agents/claude/shared/CLAUDE.md` | Claude's config root |
| `agents/codex/shared/AGENTS.md` | Codex's config root |
| `agents/bob/shared/rules/global-development-standards.md` | Bob's `rules/` directory |

Placement is not gated; uniform placement is for the reader. The block's content is fixed
by this spec, because the gate deliberately asserts nothing about it and a reviewer
otherwise has nothing to check criterion 1 against:

````markdown
<!-- shared-standards:begin -->
## Guardrails

### CI Verification

Run a guardrail command bare. Never pipe one into `tail`, `head`, or `grep`, never send
its output to `/dev/null`, and never append `|| true`: a pipeline reports the last
command's exit status, so the real failure disappears. When output has to be captured,
enable `pipefail` first — and note that zsh spells the array `pipestatus`, lowercase and
one-indexed, so `${PIPESTATUS[0]}` reads as empty there. Regenerate generated artifacts
before the check runs, not after it passes.

Before claiming a check is green, or that work is done or mergeable, run
`git status --porcelain` and read it. Any untracked file means not green: an unadded
artifact is invisible to every gate that discovers its subjects from version control, so
the green run proved nothing about it.

### Git Safety

At the shell, never run `git reset --hard`, `git clean -fd`, `rm -rf`, or `rm -f`. Recover
with `git restore`, `git stash`, or `git revert`, and delete recoverably — `trash` on
macOS, `gio trash` on Linux. Force pushes, with a lease or without one, are the user's to
run rather than yours.

Never chain a command that might be denied or fail with one that must still run, and never
put a destructive operation in a chain at all. A denied or failed first step leaves the
rest of the chain unrun, and the reported error names the wrong operation.

### Honesty & Decision Framing

Claims are hypotheses. A reported root cause, a review finding, a status line, or a
recalled memory is a lead, not a fact; verify it against the source or the artifact before
acting on it. Verify a historical claim about a repository with `git log` or `gh` and cite
the output — recollection of what a file used to contain is a hypothesis too.

Act on anything easily reversed, stating the assumption; a reversible naming or numbering
choice is taken and flagged, never blocked on. State a judgment call as a decision with
its rationale rather than handing the choice back, and surface the decisions that
genuinely need an answer one or two at a time. Ask before committing to an interface, a
data model, an architecture — including a toolchain floor such as a minimum supported
compiler version — or a destructive or external write. A question is not a task: answer it
and stop.

Do authorized follow-up work rather than offering it back. Report what ran, what did not,
An exhausted review budget without approval is reported as exactly that, never as clean.
<!-- shared-standards:end -->
````

Block content is agent-neutral — no config path, no invocation syntax, no agent-specific
file name — because byte identity across agents is otherwise unreachable. It also has to
satisfy the deployed-reference rules, since it ships to `agents/*/shared`: no bare record
number, no bare issue number, no concrete record path. The text above satisfies them.

### Consolidation, not addition

Every rule the block absorbs is removed from where it was, or the file states it twice.
Six removals in each of `agents/claude/shared/CLAUDE.md`,
`agents/codex/shared/AGENTS.md`, and `content/instructions/global-development-standards.md`
(line numbers are `content/instructions/global-development-standards.md`'s; Claude's copy
runs two to three lines shorter from its shorter opening bullet):

| Removed | Absorbed into |
|---------|---------------|
| Philosophy bullet `**Claims are hypotheses**` (`:24`) | Honesty & Decision Framing, paragraph 1 |
| Philosophy bullet `**Bias toward action**` (`:25`) | Honesty & Decision Framing, paragraph 2 |
| Reviewing code, trailing sentence `An exhausted budget without approval…` (`:41`) | Honesty & Decision Framing, paragraph 3 |
| CLI tools table, `trash` row cell `recoverable delete. **Never use `rm -rf`**` (`:91`) | Git Safety, paragraph 1; the cell keeps `recoverable delete` |
| Commits bullet `All force pushes … && chain` (`:115`) | Git Safety, both paragraphs |
| Workflow paragraph `**A check's exit code is the truth.**` (`:127`) | CI Verification, paragraph 1 |

Nothing else is a duplicate. Four rules read as near neighbours and stay put because they
say something the block does not: `A new test or gate isn't done until its first real
run's findings are reported` (Testing), `Unit tests green ≠ working` (Done means proven),
`Before committing: … all green first` (Workflow), and `CI green ≠ mergeable ≠ done`
(Workflow, about polling a pull request's state).

Bob's rules file carries none of the six and only gains the block.

Two losses in consolidation, both deliberate. The force-push rule drops the clause `are
denied by settings policy`, which describes Claude's permission configuration and cannot
be stated agent-neutrally; the operative half — a force push is the user's to run —
survives. The `&&`-chain rule's subject was `a possibly-denied command`, which the issue's
wording would have narrowed to destructive ones; the block keeps both, so a chain whose
first step may be denied for any reason is still covered.

### The gate

`scripts/check-shared-standards.sh`, wired into `just verify` through a new
`shared-standards-check` recipe.

Contract, matching `scripts/check-deployed-references.sh`:

- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Repository root derived from `${BASH_SOURCE[0]}/..`; one optional argument overrides it,
  which is how the suite points the checker at a fixture tree.
- Four literal scan roots, each of which must exist or the run exits 2:
  `content/instructions`, `agents/claude/shared`, `agents/codex/shared`,
  `agents/bob/shared`. A missing canonical file is also exit 2. No glob: a new agent tree
  is a script edit, the same residual `scripts/check-carrier-drift.sh` accepts for its
  manifest.
- `rg` missing, or more than one argument: exit 2. As in the sibling checker, the `rg`
  guard is not exercised by the suite — reproducing it would need PATH manipulation the
  rest of the suite has no use for.
- Findings to stderr as `shared-standards: <class>: <file>` or
  `shared-standards: <class>: <file>:<line>`; exit 1.
- A one-line summary on success, exit 0.

Detection follows `scripts/check-carrier-drift.sh`: scan, plus a manifest that closes the
scan's false negative. The scan checks every block found under the four roots, so a block
copied into another file there is covered without a script edit. The manifest names the
canonical file and the three deployed files, each of which must hold exactly one block, so
a deleted or mistyped marker fails naming the file instead of vanishing from the scan.

Order matters: the canonical block is the comparison source, so it is resolved first. If
it is missing, duplicated, unterminated, or under-shaped, the run reports that one finding
and exits 1 without evaluating any mirror — three spurious `block-drift` findings against
an empty string would bury the real one.

Finding classes and the line each reports:

| Class | Condition | Line reported |
|-------|-----------|---------------|
| `missing-block` | a manifest file has no begin marker | none; file only |
| `duplicate-block` | a file has a second begin marker | the second begin marker |
| `unterminated-block` | a begin marker with no end marker after it | the begin marker |
| `canonical-shape` | the canonical block has fewer than three `###` subsections | the canonical begin marker |
| `block-drift` | a block differs from the canonical block by any byte | the drifted file's begin marker |

`canonical-shape` is the fail-closed guard: without it, emptying the canonical block would
leave the gate green over nothing. It counts subsections and reads none of their text,
which is the line the decision record draws. It bounds vacuity, not quality — three empty
subsections still pass, and review is what stops that.

### The untracked-file gate

`content/skills/verification-before-completion/SKILL.md` has a Gate Function in a fenced
block whose steps are numbered 1 to 5. A new step 5 is inserted and the existing step 5
becomes 6:

```
5. ACCOUNT: For a done, passing, or mergeable claim, run `git status --porcelain`
   Any untracked file means not green
6. ONLY THEN: Make the claim
```

The Common Failures table gains one row: Claim `CI green / mergeable`, Requires
`Guardrail exit 0 and clean git status --porcelain`, Not Sufficient `Green checks with
untracked files`.

The block and the skill both carry this rule, and they are not duplicates of each other:
the block states the rule for every agent in its always-loaded instructions, and the skill
is the procedure that applies it at the moment a completion claim is about to be made. The
block owns the rule; the skill owns the step.

## Failure modes

| Mode | Handling |
|------|----------|
| A rule is added to one copy only | `block-drift` names the file and its begin marker |
| A copy's block is deleted | `missing-block` names the file |
| A copy's begin marker is mistyped | `missing-block`; the manifest is what catches it, since the scan no longer sees the block |
| The canonical block is emptied to make the gate pass | `canonical-shape`, reported alone |
| The block is duplicated by a bad merge | `duplicate-block` names the second marker |
| An end marker is lost | `unterminated-block` names the begin marker |
| Agent-native prose outside the block differs | passes; that divergence is the point |
| A stale block is copied into another file under a scan root | the scan finds it and `block-drift` names it |
| A scan root is removed or renamed | exit 2, not a silent pass |
| The canonical file is removed | exit 2, not a silent pass |
| Whitespace-only drift | `block-drift`; the comparison is byte-exact |

## Test plan

`scripts/check-shared-standards-test.sh` builds a fixture tree under
`mktemp -d "${TMPDIR:-/tmp}/shared-standards-test.XXXXXX"` with a `trap cleanup EXIT`
guarded on that prefix, so no absolute home path enters a tracked file. `reset_fixture`
writes the canonical file and all three mirrors with a valid, identical block.

One case per failure-mode row, plus the baseline:

- baseline fixture passes;
- drift in each of the three mirrors independently — three cases, so a checker that
  compares only one mirror cannot pass;
- a mirror whose block is absent; a mirror whose begin marker is mistyped while its body
  remains;
- the canonical file whose block is absent, asserting `missing-block` and that no
  `block-drift` is reported alongside it;
- duplicated begin marker; begin marker with no end marker;
- canonical block with two subsections;
- trailing-whitespace-only drift;
- divergent prose outside the block passes;
- a drifted block in an unlisted file under a scanned tree, which the scan must catch
  without a manifest entry;
- a removed scan root, a removed canonical file, and a two-argument invocation all exit 2.

Both new scripts are tab-indented, so `scripts/list-shell-sources.sh` gets no edit.

`just test` and `just lint` discover their subjects with `git ls-files`, so an unstaged
new script is invisible to them while the `Justfile` edit for `shared-standards-check`
takes effect immediately — a run that looks complete having never executed the new gate or
its suite. Both scripts must be `git add`ed before `just verify` proves anything, and the
evidence for criterion 7 is `just test`'s trailing `test: N suites passed` line showing
`N` one higher than on `main`. This is the same failure the change adds to
`verification-before-completion`, arriving first in its own implementation.

## Not in scope

- No renderer or generator for the instruction copies, and no fixer recipe that rewrites a
  drifted mirror. The decision record covers both.
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

1. All three deployed instruction files carry the block above, byte-identical to the
   canonical copy.
2. `content/instructions/global-development-standards.md` carries the canonical block.
3. Each of the six consolidation rows has been applied to all three long copies.
4. `verification-before-completion`'s Gate Function carries the new step 5 and the
   renumbered step 6, and the Common Failures table carries the new row.
5. `scripts/check-shared-standards.sh` and its suite exist, match the contract above, and
   are reached by `just verify`.
6. Each failure-mode row has a case in the suite, and each case has been observed to fail
   for its own class before the implementation made it pass.
7. `just verify` is green with both new scripts staged, and `just test` reports one more
   suite than `main` does.
