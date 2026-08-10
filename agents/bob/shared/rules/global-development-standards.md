# Global Development Standards

Keep committed configuration public-safe. Host-specific values, local project
inventories, private MCP credentials, local network addresses, and absolute user
paths belong in private overlays outside this repository.

For multi-step work, write down the plan, implement in small verified steps, and
run the relevant guardrails before reporting completion. For this repository,
the guardrails are:

Host architecture and project target architectures are separate facts.
Applicable project-local instructions and policy are authoritative for target architectures.
Before
architecture-sensitive generation, build, or verification, run `preflight` and retain
its recorded host, effective targets, and relationship. Never infer a target from the
host or drop a declared target because it differs from the current machine.

```sh
shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh
shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh
./install-test.sh
./scripts/check-public-safety.sh
```

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

Do authorized follow-up work rather than offering it back. An exhausted review budget
without approval is reported as exactly that, never as clean.
<!-- shared-standards:end -->
