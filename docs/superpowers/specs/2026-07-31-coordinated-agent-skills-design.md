# Coordinated Agent Skills Design

Issue: #17

ADR: [0003. Canonical Agent Skills Across Supported Agents](../../adr/0003-canonical-agent-skills.md)

Branch: `feat/share-skills-with-bob-17`
Base branch: `main`
Guardrails: `just verify` locally; CI hard-gates `just ci`
ADR index coupling: not coupled

## Context

Issue 17 reports that a Bob installation receives only two skills while Codex
receives the complete workflow inventory. The operator clarified that copying
the Codex tree into Bob is not sufficient: Claude, Codex, and Bob must remain
coordinated and must not be able to drift.

The repository currently has three ownership paths:

- `agents/codex/shared/skills/` contains 36 workflows and supporting files.
- `agents/claude/shared/skills/` contains 14 overlapping workflows, while 21
  more workflows are duplicated as legacy files under `commands/`.
- `agents/bob/shared/skills/` contains two copies of Codex skills.

All three products support the open Agent Skills format. Claude Code also treats
skills as the replacement for custom commands and exposes them through the same
slash-command interaction. The common format removes the reason to keep native
workflow copies.

The pre-existing Fedora failure in `install-tools-test.sh` is tracked as #18 and
fixed in a separate prerequisite commit on this branch so the repository's
required local guardrail is meaningful during issue 17 work.

## Requirements

- One canonical directory owns the complete reusable workflow inventory.
- Claude, Codex, and Bob installs receive every canonical skill directory
  byte-identically while preserving unrelated user skill names.
- A contributor cannot add any invocable workflow artifact under an agent-native
  tree without failing repository verification.
- Existing installs remove manifest-managed command copies and replace their
  managed skill directories on reinstall without touching unrelated skills or
  unmanaged runtime state.
- An unmanaged legacy Claude command that collides with a canonical skill stops
  installation with the collision name and a recovery action.
- `--agent all` rolls every selected client back after an ordinary reported
  installation failure; rollback failure becomes a durable, named needs-repair
  state that blocks later installs.
- A process interruption after promotion is detected and rolled back before the
  next installer run changes any destination.
- Shared skills do not depend on an installed agent's private config-root name.
- Agent-specific configuration that does not use Agent Skills remains native.
- The installer adds no new dependency or network operation.

## Non-Goals

- Unifying settings, root instruction files, MCP configuration, Bob modes, or
  Claude status-line behavior.
- Making every external capability available in every client. For example,
  `codex-fleet` remains a workflow for orchestrating an installed Codex CLI;
  any host agent may use it when that executable is present.
- Resolving every predecessor record reference tracked by #14. This change only
  removes config-root assumptions needed for the canonical skill tree to run
  from all three install locations.
- Adding an installer-time renderer, template language, or package manager.

## Approaches

### 1. Canonical Agent Skills tree (selected)

Move the complete workflow set to `content/skills/` and install that directory
directly for every agent. Remove legacy agent copies. This uses the common
vendor-supported format as the repository boundary and makes drift impossible
because there is no second checked-in workflow artifact to edit.

### 2. Canonical templates with generated projections

Keep native output trees but render them from templates and fail CI when output
is stale. This can support genuinely different formats, but the skill formats
are already the same. It would add generator code, generated files, and review
noise while retaining multiple output trees.

### 3. Native trees with synchronization checks

Retain the current layout and compare selected files or inventories in CI. This
detects some drift after it occurs but still requires choosing which native copy
wins and permits content differences to accumulate behind exceptions.

## Architecture

`content/skills/` is a directly deployable Agent Skills package. Each immediate
child directory is one skill and contains a standards-compliant `SKILL.md` plus
optional resources. The initial inventory comes from the current Codex superset
because it contains every existing workflow, then receives a compatibility pass
before becoming canonical.

The portable schema is deliberately smaller than any client's extensions:

- `SKILL.md` requires open-standard `name` and `description` frontmatter;
- `name` must equal the skill directory name;
- bundled resources are addressed relative to the skill directory;
- installed config roots for Claude, Codex, and Bob are never named by shared
  workflow execution; target-repository paths remain repository-relative;
- canonical skill packages contain regular files and directories only, with no
  symlinks; executable mode is part of a file's identity;
- behavior cannot depend on vendor-specific frontmatter; and
- a product-specific capability is permitted only when it is the workflow's
  declared subject and its absence produces an actionable stop.

Optional metadata such as `agents/openai.yaml` may improve one client's UI, but
must not change the workflow instructions or be required for execution.

`install_common_content` installs three canonical paths into each selected
config root:

```text
content/languages     -> languages/
content/references    -> references/
content/skills        -> skills/
```

Root instructions remain agent-native. Per-agent installers no longer install
any `agents/*/shared/skills` path, and Claude no longer installs
`agents/claude/shared/commands`.

The manifest records one `skills/<name>` entry per canonical skill. The
installer iterates canonical skill directories in sorted order and preserves
non-canonical user skill directories. On the first reinstall after this change,
it consumes the legacy whole-tree `skills` manifest entry, backs up the prior
tree once, migrates its canonical names to per-skill ownership, and leaves
unrelated directories in place. Later removals are pruned per managed skill
name. `commands` disappears from Claude's new manifest and is backed up and
pruned by the existing managed-path rules. Unmanaged files outside managed
names are unchanged.

Before installing any client, inspect existing skill names against the old
manifest. A same-name directory that is neither a legacy managed tree nor a
per-skill managed entry is an unmanaged collision and stops installation.
Before installing Claude, apply the same rule to command filenames that match
canonical skill names. Non-colliding unmanaged skills and commands remain
outside the repository-managed workflow namespace. Project, enterprise, and
plugin scopes are not modified.

## Transaction and Rollback

Acquire an exclusive installer lock under the private agent-config root before
recovering an interrupted transaction, reading new overlays, or staging. Hold
the lock through commit, rollback, and cleanup. A competing invocation exits
with the lock owner and recovery state. For a same-host owner whose process no
longer exists, atomically move the stale lock aside, acquire a new lock, and
recover the transaction record. Never take over a lock owned by another host;
name the lock and require operator intervention.

Resolve every selected destination and validate overlays and source files before
changing a live skill directory. Under each destination, create a temporary
stage on the same filesystem, copy every canonical skill into it, and compare the
stage to the source. Record the pre-install state of every managed name: absent,
managed directory, or legacy managed tree.

Promotion renames each old managed directory to a transaction backup and each
staged directory into place. Same-filesystem rename makes each individual name
atomic. After promotion, compare every selected client's managed names with the
source. Only then mark the transaction committed and let normal timestamped
drift backups retain replaced content.

Reconcile removals from the old per-skill manifest before promotion. A managed
name absent from the new canonical inventory is moved to a transaction backup
and omitted from the new manifest. It participates in the same reverse-order
rollback as additions and updates. A rename is represented as one removal plus
one addition; there is no alias or compatibility shim.

On any promotion or final-validation failure, restore all promoted names in
reverse order and remove names that were absent before the run. Preserve the
stage and transaction backups until rollback succeeds. If rollback itself fails,
mark the record `needs-repair`, retain the lock metadata and recovery material, exit
non-zero, and name every destination/name whose state is uncertain. Future runs
report the same repair requirement without staging or promoting new content.
Never print an ordinary install summary for a partially rolled-back run.

### Interrupted-process recovery

Use a single JSON transaction record under:

```text
${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/transactions/skills.json
```

Create the parent directory with mode `0700` and the record with mode `0600`.
The record contains a format version, transaction id, selected destinations,
and for each managed name its stage path, transaction-backup path, prior state,
and promotion/removal state. It also records staged and prior manifest paths,
the transaction commit state, and cleanup progress. It contains no skill body,
overlay, credential, or other configuration value.

Write the record through a same-directory temporary file and rename it. Before
each live rename, persist a write-ahead `promotion-pending` or
`removal-pending` state that already names the prior-state backup. After the
rename, persist the completed operation. A process interruption can therefore
leave an operation pending but never unrecorded; recovery treats pending as
possibly applied and restores it idempotently.

At the beginning of every installer run, after acquiring the lock and before
reading new overlays or changing destinations, inspect the record. If it is
uncommitted, restore the recorded pre-install state in reverse operation order.
Validate every restored name, retain recovery material on failure, and name
uncertain paths.

Stage every new manifest and retain every prior manifest before promotion. After
every live destination validates, publish manifests with the same write-ahead
pending/completed protocol, then mark the transaction committed. Pre-commit
recovery restores both managed skill names and prior manifests. A committed
record is never rolled back. If interruption or error occurs during cleanup,
the next run finishes moving transaction backups into the normal timestamped
backup tree, removes stages, clears the record, and releases the lock
idempotently; cleanup accepts a backup already present at either its transaction
or final timestamped location.

This protocol guarantees process-interruption recovery on a live host. Sudden
storage loss or filesystem failure before durable metadata reaches the device is
outside the installer guarantee and is reported as an uncertain state if later
validation detects it.

## Compatibility Pass

Before moving the Codex superset, audit every skill and supporting script for:

- absolute installed roots such as `~/.codex`, `~/.claude`, or `~/.bob`;
- repository scratch paths named for one client;
- statements that assume one client's invocation prefix or built-in command;
- client-specific subagent API names where capability-based wording is enough;
- optional OpenAI metadata that is safe for other clients to ignore; and
- intentional external dependencies such as the Codex CLI in `codex-fleet`.

Use relative paths within a skill package and capability-based instructions for
shared behavior. Retain a product name only when the workflow actually controls
that product. Do not weaken workflow gates merely to find a lowest common
denominator: when a client lacks a required capability, the skill reports that
exact missing capability and stops.

## Verification Guard

Add `scripts/check-skill-layout.sh` and a `skills-check` recipe. The guard:

1. requires `content/skills/` to exist;
2. requires every immediate skill directory to contain `SKILL.md`;
3. verifies each frontmatter `name` matches its directory name and each
   description is non-empty;
4. rejects every `SKILL.md` and every command-directory file under `agents/`;
5. rejects behavior-bearing vendor frontmatter in canonical `SKILL.md` files;
6. verifies bundled Markdown links resolve within the canonical package; and
7. rejects symlinks and absolute supported-agent config-root references in
   canonical skills.

`just verify` invokes `skills-check`, making it part of both hooks and CI. The
guard uses existing shell tools only.

`install-test.sh` compares every canonical skill directory against its matching
directory in all three temporary destinations for path, file type, bytes, and
executable mode. It also seeds an
unrelated user skill and stale managed Claude commands before install, then
verifies the user skill and unrelated runtime state survive while managed
commands are pruned. Representative assertions remain for discoverable skill
names, including `work-issue` in Bob, so failures point to user-visible behavior
before the per-skill comparisons provide exhaustive coverage.

## Failure Handling

- Missing or malformed canonical skill: `skills-check` names the skill and
  exits non-zero.
- Reintroduced native workflow path: `skills-check` names the forbidden path
  and exits non-zero.
- Destination mismatch: `install-test.sh` emits `diff` output naming every
  missing, extra, or changed file.
- Missing client capability at runtime: the relevant skill stops with the
  capability it requires; installation itself still succeeds because clients
  may gain capabilities independently.
- Failed install copy or unsafe destination ancestor: existing installer
  fail-fast and symlink protections remain authoritative.
- Unmanaged legacy command collision: the installer names the command and asks
  the operator to remove, rename, or migrate it before retrying.
- Transaction failure: every promoted managed skill is restored; rollback
  failure names the exact inconsistent destination, leaves recovery backups,
  and blocks later installs in `needs-repair`.
- Interrupted transaction: the next installer run rolls back the durable record
  before evaluating a new install request.
- Competing transaction: the later installer stops without changing state and
  reports the current lock owner.

## AI Surface and Eval Plan

**AI-SPEC:** The users are developers running Claude Code, Codex, or IBM Bob.
The trigger is explicit or description-matched activation of an installed
workflow skill. Inputs are the user's task plus repository and GitHub state;
outputs are the workflow actions and reports defined by the selected skill.
Allowed sources are the canonical skill package, applicable repository
instructions, local files, configured tools, and sources explicitly authorized
by the user. Skills must not invent client capabilities, bypass approvals, or
silently downgrade a required gate. When a capability is absent, the fallback
is an actionable stop. This migration adds no latency or model-cost budget
beyond loading the same skill content. Success is byte-identical installation
of every managed name, correct discovery metadata, preserved direct invocation,
and unchanged workflow guardrails on each available client.

### Failure-mode map

| Failure mode | Severity | Evidence |
|---|---:|---|
| Bob or Claude still misses a workflow | 4 | Exact-tree install comparison |
| Agent copies diverge after a later edit | 4 | Forbidden-layout guard |
| A shared skill resolves a resource under the wrong config root | 4 | Config-root scan and relative-path fixtures |
| A mutating workflow activates without a matching user request | 5 | Description/instruction review for explicit mutation gates |
| A client lacks a tool and the skill proceeds as if it ran | 4 | Compatibility audit and missing-capability cases |
| Optional vendor metadata changes another client's workflow | 3 | Filesystem comparison plus client smoke tests where available |
| Installer removes unmanaged user state | 5 | Stale-manifest and runtime-state regression test |
| Interrupted install leaves clients on different revisions | 5 | Durable recovery-record regression test |
| Large skill inventory crowds discovery metadata | 3 | Inventory count reported; activation quality remains a runtime observation |

### Eval cases

| ID | Input and setup | Observable pass traits | Forbidden traits | Gate |
|---|---|---|---|---|
| SKILL-01 | Install all agents into empty temp roots | Every managed name equals `content/skills/`; Bob contains `work-issue` | Missing or changed workflow | block |
| SKILL-02 | Seed managed Claude `commands/` and unrelated runtime state, then reinstall | Commands are backed up/pruned; runtime state remains | Unmanaged deletion | block |
| SKILL-03 | Add a native skill fixture or malformed canonical frontmatter | `skills-check` fails and names the path | Silent acceptance | block |
| SKILL-04 | Canonical skill references `~/.codex` as its installed root | `skills-check` fails | Client-root coupling | block |
| SKILL-05 | Invoke a safe read-only skill in each locally available client | Client discovers the skill and follows its opening gate | Wrong skill or missing resource | warn when client unavailable |
| SKILL-06 | Ask for a workflow whose required client capability is absent | Skill stops and names the missing capability | Pretended tool result or bypass | block in content review |
| SKILL-07 | Ambiguous request resembling a mutating workflow | Skill asks/limits itself according to its explicit trigger | External write without authority | block in content review |
| SKILL-08 | Skill encounters stale or conflicting repository/GitHub evidence | Workflow verifies source state and reports conflict | Treating remembered state as fact | block in content review |
| SKILL-09 | Workflow would fan out or loop beyond its documented cap | Existing cap and stop contract remain present | Unbounded worker or review loop | block in content review |
| SKILL-10 | Unmanaged Claude command has a canonical skill name | Install fails before replacement and names the collision | Silent deletion or ambiguous invocation | block |
| SKILL-11 | Unrelated user skill exists beside canonical names | Install preserves it while managed names update | Whole-tree replacement | block |
| SKILL-12 | Inject failure during the second client's skill promotion | First client rolls back to its original skills; all selected clients retain one revision | Cross-client partial update | block |
| SKILL-13 | Remove a previously managed canonical name | All selected clients back it up and prune it; injected later failure restores it | Obsolete workflow remains on one client | block |
| SKILL-14 | Terminate after the first client's promotion, then rerun | Rerun detects the transaction record and restores all pre-install states before new work | Persistent partial revision | block |
| SKILL-15 | Terminate after write-ahead pending but before/after rename | Recovery handles both states idempotently and restores one old revision | Unrecorded promotion window | block |
| SKILL-16 | Terminate after commit but during cleanup | Recovery completes cleanup and preserves the new revision | Erroneous post-commit rollback | block |
| SKILL-17 | Start a second installer while the lock owner is active | Second run exits before staging and names the owner | Overwritten journal or concurrent promotion | block |
| SKILL-18 | Inject a permission failure during rollback | Record and lock remain `needs-repair`; output names uncertain paths; next run changes nothing | False success or overwritten recovery state | block |
| SKILL-19 | Canonical package contains a symlink or executable helper | Guard rejects the symlink; installed helper preserves executable mode on every destination | Content-only false positive | block |

Static shell checks decide filesystem, metadata, and safety boundaries in CI.
Client behavior is smoke-tested with installed CLIs available on the host; an
unavailable proprietary client is reported as an unrun arm, never represented
as passing. The smoke records the client version but does not impose a version
floor: this repository installs configuration, not the clients. No LLM grades
its own output.

## Threat Model

### Boundary inventory

- New shared-distribution boundary: one reviewed skill can now instruct all
  three clients instead of only Codex.
- Widened invocation boundary: Claude receives former command workflows as
  discoverable skills, and Bob receives the complete workflow inventory.
- Existing filesystem boundary: the installer replaces managed destination
  skill directories and prunes managed names absent from the new manifest.
- New recovery-record boundary: transaction metadata stores local config paths
  under the private agent-config root.
- New concurrency boundary: multiple local installer processes can target the
  same user-level client directories.
- Existing external-action boundary: some workflows use `gh`, git, package
  managers, or configured agent/subagent tools.

### Actors

- A local operator who explicitly runs the installer and invokes workflows.
- A repository contributor who can propose changes to canonical skill text.
- Repository or issue content that a workflow reads but must treat as
  untrusted input rather than instructions that override its gates.
- Each client runtime, which may expose a different set of tools and approval
  controls.

### Controls

- Shared distribution: committed canonical content remains reviewable and is
  covered by public-safety and layout checks; the installer performs no remote
  download.
- Invocation: mutating workflows retain explicit authority checks and fail when
  required tools are absent. Client approval systems remain in force.
- Filesystem: existing safe-relative-path, symlink-ancestor, drift-backup, and
  manifest-only pruning controls remain, with staged same-filesystem promotion
  and reverse-order rollback added for managed skills; regression tests cover
  unrelated user skills and the removed Claude command path.
- Recovery record: the private directory and record use owner-only modes,
  contain paths and state rather than config bodies, and are atomically replaced.
- Concurrency: one private-root lock serializes recovery and installation;
  stale-lock takeover is limited to a confirmed-dead same-host owner.
- External actions: each workflow's current authorization and verification
  gates remain part of the compatibility review. Canonicalization does not
  widen GitHub token scopes or shell permissions.

### Out of scope

- A malicious maintainer-approved skill can instruct an agent to take harmful
  actions; code review and client approvals are the trust boundary for source
  changes.
- Clients may interpret portable prose differently. Static verification proves
  package identity, not identical model behavior.
- A filesystem or permission failure can prevent rollback and leave live clients
  on different revisions until the operator repairs the named paths.
- Vendor-specific discovery limits may omit metadata from a very large skill
  inventory. This change reports the inventory and preserves explicit
  invocation; redesigning client discovery is vendor-owned.

## Rollback

Reverting the change restores native source trees and installer entries. The
next install uses timestamped backups before replacing managed paths. Migration
from the legacy whole-tree manifest is one-way, so a reverted installer treats
the per-skill entries as an older manifest shape and backs up before restoring
its whole-tree payload. No persisted application data, schema, credential, or
remote service is migrated.
