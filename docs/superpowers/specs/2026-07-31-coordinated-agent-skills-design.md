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
- The filesystem-managed portion of `--agent all` either commits one complete
  revision—including native files, common content, canonical skills, legacy
  removals, and ownership manifests—to every selected client or rolls every
  selected client back after an ordinary reported failure; rollback failure
  becomes a durable, named needs-repair state that blocks later installs.
- A process interruption after promotion is detected and rolled back before the
  next installer run changes any destination.
- A durable `needs-repair` transaction has one explicit, validated repair path;
  no operator must edit or delete journal/lock files by hand.
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

The portable schema is deliberately smaller than any client's extensions and
is pinned to upstream Agent Skills commit
`38a2ff82958afee88dadf4831509e6f7e9d8ef4e`, specification blob
`20cf9f6b672391e3295733c7863480905de6b887`:

- `scripts/agent-skills-contract.json` records that immutable source identity
  and is the machine-readable input to the guard;
- `SKILL.md` is UTF-8 and begins with exactly four frontmatter lines: `---`, a
  plain `name: <canonical-name>` scalar, a one-line JSON-quoted
  `description: "..."` scalar, and `---`; non-empty Markdown follows;
- `name` must equal the skill directory name, contain 1–64 lowercase ASCII
  letters, digits, or hyphens, neither begin nor end with a hyphen, and contain
  no consecutive hyphens;
- `description` contains 1–1024 Unicode scalar values;
- names must be unique under ASCII case folding and must not match the
  checked-in union of documented built-in, bundled, and mode-command names for
  Claude, Codex, or Bob;
- bundled resources are addressed relative to the skill directory;
- every package-relative component is 1–100 ASCII characters matching
  `[A-Za-z0-9][A-Za-z0-9._-]*`, does not end in a dot, is unique under ASCII
  case folding within its parent, and keeps the complete relative path at or
  below 512 bytes; non-ASCII normalization and host-reserved hidden names are
  excluded rather than normalized differently by supported filesystems;
- installed config roots for Claude, Codex, and Bob are never named by shared
  workflow execution; target-repository paths remain repository-relative;
- canonical skill packages contain regular files and directories only, with no
  symlinks; executable mode is part of a file's identity;
- behavior cannot depend on vendor-specific frontmatter; and
- a product-specific capability is permitted only when it is the workflow's
  declared subject and its absence produces an actionable stop.

Optional metadata such as `agents/openai.yaml` may improve one client's UI, but
must live outside `SKILL.md` frontmatter, must not change the workflow
instructions, and must not be required for execution.

The common installer stages three canonical paths for each selected config
root:

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
non-canonical user skill directories. Later removals are pruned per managed
skill name. Unmanaged files outside managed names are unchanged.

The legacy manifest contains only whole-tree `skills` and, for Claude,
`commands` entries; it does not identify children. This change therefore checks
in `scripts/legacy-skill-ownership.json` before moving the old sources. For each
agent it records every old managed skill/command name and the tree identity of
its shipped bytes, file types, and executable modes. The installer trusts
neither a whole-tree manifest nor a matching name by itself.

For the one-time migration, a child whose identity matches the historical
ledger is proven managed. A non-canonical name absent from the ledger is proven
unrelated and preserved. Every other present child is ambiguous: this includes
a current canonical name with user-replaced bytes and a historically managed,
now-removed name with drift. Installation stops before staging and requires an
explicit repeatable `--legacy-resolution agent:name=replace|remove|preserve`.
`replace` is valid for a canonical-name collision and backs it up before
installing the canonical package; `remove` is valid for a former managed name
and backs it up before pruning; `preserve` is valid only for a non-canonical
name and leaves it unmanaged. The chosen resolutions are copied into the
transaction journal so interruption recovery never asks again mid-transaction.

After classification, the installer copies only proven-managed children and
children explicitly resolved as `replace` or `remove` into per-child transaction
entries. A canonical child missing before migration has prior state `absent`;
one copied entry has prior state `legacy-backup:<name>`. Recovery and retained
timestamped backup roots are mode `0700`; files retain their recorded mode.
Copies use `lstat` semantics: a descendant symlink is copied as a symlink and is
never followed, while sockets, devices, and other special files stop migration
before live mutation. Proven-unrelated and `preserve` children are never read
recursively or copied. Rollback restores only recorded per-child entries and
never replaces the enclosing tree.

Claude command migration uses the same historical ownership ledger and
resolution rules. Only proven-managed or explicitly resolved command files are
copied to transaction entries and restored independently on rollback. Other
command files remain in place. The new manifest contains neither a whole-tree
`skills` nor `commands` entry.

The ledger and journal use identity algorithm `tree-v1-git-blob`. `absent` is
a separate tagged value. For a present tree, walk with `lstat`, reject paths
that are not valid UTF-8 or contain control characters, and sort relative path
UTF-8 bytes in unsigned byte order. Include directories so empty directories
are represented. Encode each entry without delimiter ambiguity as: one type
byte (`d`, `f`, or `l`), an unsigned 64-bit big-endian path-byte length, path
bytes, one executable byte (`1` when any executable bit is set on a regular
file, otherwise `0`), an unsigned 64-bit big-endian payload length, and payload
bytes. A regular-file payload is its content, a symlink payload is its link
target without traversal, and a directory payload is empty. Hash the complete
stream with `git hash-object --stdin` and store both the repository Git object
format and result. Root ownership and permission bits do not participate.
Ledger and journal records reject an unknown identity version or object format
before mutation. Fixed empty-directory, executable, Unicode-path, symlink, and
absent goldens for each Git object format make implementations comparable
across supported hosts.

Before installing any client, classify existing skill names from the per-name
manifest or the historical-ledger protocol above. An unowned same-name
directory or Claude command is an unmanaged collision and stops installation
unless the operator supplies the valid explicit resolution. Non-colliding
unmanaged skills and commands remain outside the repository-managed workflow
namespace. Project, enterprise, and plugin scopes are not modified.

## Installation Ordering, Transaction, and Rollback

Resolve and canonicalize every selected config destination, reject duplicates,
and sort by canonical path. Atomically create a unique mode-`0600` journal in
state `locking` before acquiring `.agent-config-skills.lock` in each destination
in that order. A lock is a regular mode-`0600` JSON file containing the
execution identity, PID/start identity, transaction id, private root, journal
path, its canonical destination, the complete sorted selected-destination list,
and that list's canonical JSON digest. Every lock in the transaction carries
the same scope digest.
Create and validate that complete file at a random sibling path, record
the sibling path, device, inode, and content digest as acquisition `pending` in
the journal, then use a same-directory hard link to publish
`.agent-config-skills.lock` atomically with no overwrite. A failed link means
another owner won; an interruption before the link leaves only the recorded
sibling file and no apparent lock. After publication, require the lock name to
resolve to the pending device, inode, and digest, unlink the sibling name, and
record `held`. Pending recovery checks both names against that recorded identity
and removes only matching links; cleanup leaves neither sibling nor lock name.

After all locks are held and before any live promotion, publish an immutable
mode-`0600` transaction header inside each destination's contained transaction
directory. Each header repeats the transaction id, full destination list/scope
digest, identity algorithm, and journal generation digest. Validate a matching
header in every selected destination before entering `open`. Reconstruction
requires the complete list from at least one valid lock/header and a matching
header or lock from every destination on that list. Missing or conflicting
scope evidence makes automated release impossible and reports the exact
destination whose original membership cannot be proved.

Hold all acquired locks through commit, rollback, and cleanup. If any
acquisition fails, journal and release locks acquired by the current process in
reverse order before exiting. Before unlinking a lock, require its current
device, inode, and content digest to match the held identity, write
`release-pending`, unlink, and write `released`; an identity mismatch becomes
`needs-repair` and never removes the replacement owner's lock. This
per-destination identity serializes overlapping selections even when
invocations use different `AGENT_CONFIG_PRIVATE_DIR` values and prevents
deadlock for selections containing the same roots.

Supported destinations are host-local filesystems. Before creating a journal,
query the OS filesystem type and reject network/shared types (including NFS,
SMB/CIFS, AFP, and SSH/FUSE network mounts); an unknown type stops with the
destination and detected value. Hostname is display-only. The execution
identity is the OS machine identity plus boot identity and, when present, PID
namespace identity (Linux: machine-id, boot-id, and PID-namespace inode; macOS:
IOPlatformUUID and `kern.boottime`). The process identity also records its OS
start token, not PID alone. Automatic liveness probing or takeover is allowed
only when the complete execution identity matches and that exact PID/start token
is gone. A different execution identity, malformed metadata, or unsupported
storage topology requires the repair path and is never inferred dead from a
hostname/PID collision.

After locks are held, resolve overlays and stage every filesystem-managed source
for every selected client: agent-native files, `languages/`, `references/`,
each canonical skill name, managed legacy-command removals, and the complete
ownership manifest. Validate every stage before changing a live path. The
transaction promotes and rolls back all of those entries together, so a
manifest always describes the same committed filesystem generation. An error
after staging cannot produce an ordinary success or generic install summary:
it either restores every selected client's prior managed paths and manifest or
enters `needs-repair`. Optional external side effects such as Claude MCP
registration run only after filesystem commit and are reported separately;
they are not represented as part of the atomic filesystem transaction.

Under each destination, create a temporary stage on the same filesystem, copy
every managed payload into it, and compare the stage to the source. Record the
pre-install identity of every managed path and canonical skill name.

Promotion renames each old managed path to a transaction backup and each staged
path into place. Same-filesystem rename makes each individual path atomic.
After promotion, compare every selected client's managed filesystem generation
and manifest with the staged source. Only then mark the transaction committed
and let normal timestamped drift backups retain replaced content.

Reconcile removals from the old per-skill manifest before promotion. A managed
name absent from the new canonical inventory is moved to a transaction backup
and omitted from the new manifest. It participates in the same reverse-order
rollback as additions and updates. A rename is represented as one removal plus
one addition; there is no alias or compatibility shim.

On any promotion or final-validation failure, restore all promoted names in
reverse order and remove names that were absent before the run. Preserve the
stage and transaction backups until rollback succeeds. If rollback itself fails,
mark the record `needs-repair`, retain the lock metadata and recovery material,
exit non-zero, and name the transaction id plus every destination/name whose
state is uncertain. Ordinary install runs report the same repair requirement
without staging or promoting new content. Never print an ordinary install
summary for a partially rolled-back run.

The only exit from `needs-repair` is
`./install.sh --repair-skills <transaction-id>`. It validates the closed schema,
takes over every recorded lock only from the matching dead execution identity,
and revalidates
every live, stage, backup, manifest, and lock identity before mutation. It then
retries the same idempotent rollback. If recovery material is unavailable, it
accepts an operator-restored path only when its bytes, file types, executable
modes, and absent/present state match the pre-state identity already stored in
the journal. All destinations and prior manifests must match before the repair
enters normal cleanup and journaled lock release. Any remaining mismatch leaves
the transaction in `needs-repair`, changes no already-restored path, and prints
the next exact path/action. There is no force-accept or journal-delete option.

If neither journal generation is valid, normal repair refuses. The auditable
fallback is `--repair-skills <transaction-id> --reconstruct <repair.json>`.
The operator-supplied, closed-schema repair record names the transaction,
private root, creator execution/PID-start identity, every canonical destination,
the scope digest, the observed
device/inode/digest of each lock, and the desired versioned identity of every
live managed name and manifest. Its destination scope must exactly match the
full list and digest replicated in a valid lock/header, with matching evidence
present at every member destination; current inventory, historical ledger, live
manifests, and safely contained transaction-entry names must also all be
included. Omission is an error. The command verifies the recorded local process
instance is dead, every surviving lock/header has the supplied identity, every
live path already matches the supplied coherent state, and no path escapes a
destination. It performs no content restoration.
It archives the corrupt generations, no-follow copies of the matching locks,
and supplied repair record under an owner-only quarantine, writes a new valid
`needs-repair` generation recording the reconstruction, and then uses normal
validation, cleanup, and identity-checked release of the original locks.
Remote-host ownership, an incomplete scope, a live PID, or any identity mismatch
remains operator-blocked; the tool names the evidence still required. Thus
corruption may require the operator to restore known bytes and declare their
identities, but never to edit or delete transaction evidence by hand.

### Interrupted-process recovery

Use one unique transaction directory per invocation under:

```text
${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/transactions/skills/<transaction-id>/
```

Create the directory with mode `0700`. Keep `current.json` and
`previous.json` generations at mode `0600`. Each is canonical key-sorted JSON
with a monotonic generation, the prior generation's digest, and its own
`git hash-object --stdin` digest computed after removing the digest field. A
write creates and validates a sibling temporary generation, rotates the old
current to previous, then renames the temporary to current. Recovery chooses
the highest valid linked generation; a truncated or checksum-invalid current
falls back to the valid previous generation.

The version-1 record is a closed schema. Its top-level state is exactly
`locking`, `open`, `committed`, `cleanup-complete`, or `needs-repair`; it
contains a lowercase hexadecimal transaction id, creator execution identity,
PID/start token, private root,
selected destinations in canonical sorted order, a per-destination lock state,
and one unique operation identity for each destination plus managed name. Lock
state is exactly `planned`, `pending`, `held`, `release-pending`, or `released`.
Operation kind is exactly `promote`, `remove`, `legacy-skill`,
`legacy-command`, or `manifest`; operation state is exactly `planned`,
`pending`, `complete`, or `cleaned`. Prior state is exactly `absent`,
`per-name-backup`, or `legacy-backup:<child>`. It records every per-child
recovery entry, explicit legacy resolution, commit state, and cleanup progress.
Every prior and staged state includes its versioned tree identity so repair can
validate an operator-restored path without trusting prose. Unknown keys,
duplicate destination/name identities, out-of-order destinations, and invalid
enum transitions are invalid. An unsupported version is preserved for a
compatible installer. The record contains no skill body, overlay, credential,
or other configuration value.

All mutable recovery paths are derived and then compared with the record:
stages and transaction backups must be descendants of
`<destination>/.agent-config-transactions/<transaction-id>/`, manifests must be
`<destination>/.agent-config-manifest`, and live names must be safe relative
paths under that destination. The transaction id in every path and destination
lock must match the record. Before recovery mutates anything, canonicalize
existing ancestors without following a symlink out of the destination, reject
symlink ancestors, re-resolve the current selected roots, and require their
filesystem identities to match the recorded destinations. An intact unsupported
version stops without rewriting it and names the required compatible installer.
A structurally invalid but parseable record, malformed transition, path escape,
symlink swap, or stale overlay resolution writes a new valid `needs-repair`
generation when safe, leaves all live paths unchanged, retains locks and
recovery material, and prints the failing field and repair action.

Before each live rename, persist a write-ahead `promotion-pending` or
`removal-pending` state that already names the prior-state backup. After the
rename, persist the completed operation. A process interruption can therefore
leave an operation pending but never unrecorded; recovery treats pending as
possibly applied and restores it idempotently.

When a destination lock already exists, validate its identified record before
taking over a dead matching execution/process identity. An interrupted
`locking` record has not
entered the live-content phase: release any possibly acquired locks
idempotently and delete the record after all are absent. For an `open` record,
first take over all destinations named by that record, then restore the recorded
pre-install state in reverse operation order. Validate every restored name,
retain recovery material on failure, and name uncertain paths.

Stage every new manifest and retain every prior manifest before promotion. After
every live destination validates, publish manifests with the same write-ahead
pending/completed protocol, then mark the transaction committed. Pre-commit
recovery restores both managed skill names and prior manifests. A committed
record is never rolled back. If interruption or error occurs during cleanup,
the next run finishes moving transaction backups into the normal timestamped
backup tree and removes stages; cleanup accepts a backup already present at
either its transaction or final timestamped location.

After cleanup, mark the record `cleanup-complete`, then release destination
locks in deterministic reverse order using `release-pending` and `released`
write-ahead states. Delete the record only after every recorded lock is
confirmed absent. A crash before the first lock, between lock operations, or
after cleanup therefore always leaves a journal that proves whether live
content mutation could have begun. Orphaned `locking` or `cleanup-complete`
records in the current private root are validated and finished before a new
transaction is created.

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

1. validates the pinned source identity and rule keys in
   `scripts/agent-skills-contract.json` before consuming them;
2. requires `content/skills/` to exist;
3. requires every immediate skill directory to contain `SKILL.md`;
4. requires the exact four-line frontmatter syntax above, rejects any extra key,
   comment, block scalar, duplicate, malformed UTF-8, or trailing frontmatter
   content, decodes the JSON description with the already-required `jq`, and
   verifies its locale-independent scalar length is 1–1024 while the plain name
   matches its directory and complete pinned grammar;
5. rejects every `SKILL.md` and every command-directory file under `agents/`;
6. verifies bundled Markdown links resolve within the canonical package;
7. rejects symlinks and absolute supported-agent config-root references in
   canonical skills; and
8. rejects names in `scripts/reserved-skill-names.txt`, whose comments identify
   the supported-client documentation source and retrieval date for each group;
   and
9. enforces the portable component/path grammar and rejects nested case-fold
   collisions before checkout or installation can alias them.

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
- Ambiguous legacy child: the installer names the ledger mismatch and prints
  the valid explicit resolution values without changing live state.
- Transaction failure: every promoted managed skill is restored; rollback
  failure names the exact inconsistent destination, leaves recovery backups,
  and blocks later installs in `needs-repair`.
- Interrupted transaction: the next installer run rolls back the durable record
  before evaluating a new install request.
- Competing transaction: the later installer stops without changing state and
  reports the current lock owner.
- Invalid recovery metadata: the installer makes no live mutation; it falls
  back to a valid linked generation, writes `needs-repair` for parseable invalid
  state, requests a compatible installer for an intact unknown version, or
  requests an auditable reconstruction when neither generation is valid.
- Repaired transaction: only `--repair-skills <transaction-id>` retries the
  recorded rollback; it unblocks installation only after every pre-state and
  lock identity validates.

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
and preservation of the canonical workflow instructions. Live-model behavior
is reported separately as sampled evidence, never as a deterministic guarantee.

### Failure-mode map

| Failure mode | Severity | Evidence |
|---|---:|---|
| A client silently omits an installed workflow from its index | 4 | Exhaustive client discovery inventory |
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
| SKILL-00 | Ask each available client adapter for its actual indexed user-skill inventory after install | Sorted canonical names equal sorted indexed canonical names | Inferring discovery from files or probing only representative names | block for each available client |
| SKILL-01 | Install all agents into empty temp roots | Every managed name equals `content/skills/`; Bob contains `work-issue` | Missing or changed workflow | block |
| SKILL-02 | Seed managed Claude `commands/` and unrelated runtime state, then reinstall | Commands are backed up/pruned; runtime state remains | Unmanaged deletion | block |
| SKILL-03 | Add a native skill fixture or malformed canonical frontmatter | `skills-check` fails and names the path | Silent acceptance | block |
| SKILL-04 | Canonical skill references `~/.codex` as its installed root | `skills-check` fails | Client-root coupling | block |
| SKILL-05 | Run the exact read-only preflight prompt and fixture below | Required metadata and read-only trace predicates are observed and counted | Wrong skill, mutation, or missing resource | behavioral observation |
| SKILL-06 | Run the exact missing-Codex-CLI prompt and fixture below | Actionable capability stop predicates are observed and counted | Pretended tool result, worker, or file write | behavioral observation |
| SKILL-07 | Run the exact question-only clean-branches prompt below | Explanation with unchanged files and refs is observed and counted | External mutation without authority | behavioral observation |
| SKILL-08 | Run the exact stale-issue prompt and mock below | Read-before-write and conflict-report predicates are observed and counted | Treating prompt state as fact | behavioral observation |
| SKILL-09 | Run the exact non-converging review prompt and mock below | Documented call cap and exhausted result are observed and counted | Unbounded loop or false approval | behavioral observation |
| SKILL-10 | Unmanaged Claude command has a canonical skill name | Install fails before replacement and names the collision | Silent deletion or ambiguous invocation | block |
| SKILL-11 | Unrelated user skill exists beside canonical names | Install preserves it while managed names update | Whole-tree replacement | block |
| SKILL-12 | Inject failure during the second client's skill promotion | First client rolls back to its original skills; all selected clients retain one revision | Cross-client partial update | block |
| SKILL-13 | Remove a previously managed canonical name | All selected clients back it up and prune it; injected later failure restores it | Obsolete workflow remains on one client | block |
| SKILL-14 | Terminate after the first client's promotion, then rerun | Rerun detects the transaction record and restores all pre-install states before new work | Persistent partial revision | block |
| SKILL-15 | Terminate after write-ahead pending but before/after rename | Recovery handles both states idempotently and restores one old revision | Unrecorded promotion window | block |
| SKILL-16 | Terminate after commit but during cleanup | Recovery completes cleanup and preserves the new revision | Erroneous post-commit rollback | block |
| SKILL-17 | Start a second installer while the lock owner is active | Second run exits before staging and names the owner | Overwritten journal or concurrent promotion | block |
| SKILL-18 | Inject a permission failure during rollback; verify ordinary install refusal; fix it and run `--repair-skills <id>`; repeat with one path still mismatched | First repair restores/validates all clients and releases locks; second remains `needs-repair` and names the mismatch | False success, manual journal deletion, or install while uncertain | block |
| SKILL-19 | Canonical package contains a symlink or executable helper | Guard rejects the symlink; installed helper preserves executable mode on every destination | Content-only false positive | block |
| SKILL-20 | Start installers with different private roots but the same three destinations | One owns all destination locks; the other exits before live or journal mutation | Split journals or concurrent promotion | block |
| SKILL-21 | Seed an intact unknown version, invalid transition, duplicate name, path escape, symlink swap, stale destination, truncated current with valid previous, and invalid current/previous journals | Unsupported version requests a compatible installer; parseable invalid state enters `needs-repair`; one valid generation recovers; no valid generation requires reconstruction; live paths remain byte-identical | Executing any unvalidated live rename | block |
| SKILL-22 | Legacy whole-tree manifests contain exact historical children, user-created current-name collisions, modified former-managed names, removed historical names, and unrelated children; exercise each explicit resolution and inject termination at every boundary across three clients | Proven ownership migrates automatically; ambiguity stops or follows only the recorded resolution; rollback restores every byte/mode and preserves unrelated children | Name-only ownership, enclosing-tree replacement, or user-child loss | block |
| SKILL-23 | Fail promotion before and after every native/common path and client boundary | Every selected client's complete managed filesystem and sole manifest return to their prior identity | Manifest/filesystem skew or a partial client revision | block |
| SKILL-24 | Add empty/1025-scalar descriptions, combining characters, duplicate/unknown keys, quoted names, block descriptions, escapes, comments, malformed UTF-8, consecutive-hyphen/reserved names, and nested case-fold, non-ASCII, trailing-dot, overlength, and contract-identity fixtures under multiple locales | `skills-check` accepts only the deterministic frontmatter/path subset and rejects each invalid rule/path identically across locales | Hand-parsed ambiguity or a package accepted by only a subset of clients/filesystems | block |
| SKILL-25 | Terminate before journal `pending`, after `pending` but before hard-link publication, after publication but before `held`, after `held`, before the first release, and between every release; replace one lock before recovery | Rerun removes only the dead matching execution/process lock with matching device/inode/content identity; completed runs leave no lock, sibling, or journal | Malformed apparent lock, no-record dead lock, leaked sibling, or deletion of a replacement lock | block |
| SKILL-26 | Change `languages/`, `references/`, native files, and skills, then fail after mixed-path promotion | Rollback restores one prior identity for every managed path and manifest in all selected clients | Old skills paired with new common/native content | block |
| SKILL-27 | Corrupt both journal generations; delete one destination's lock/header before its first live operation; then exercise incomplete, live process-start, mismatched execution/scope, and complete reconstruction records after restoring coherent state/evidence | Missing scope evidence and unsafe records refuse without loss; a complete matching scope is quarantined, validated, and releases only matching locks | Inferring omitted destinations, manual evidence deletion, or accepting inconsistent state | block |
| SKILL-28 | Preserve an unrelated legacy skill containing an unreadable file, symlink, large asset, and sentinel secret while replacing one proven-managed sibling | Install succeeds without the unrelated sentinel appearing under transaction or timestamped backups; managed symlinks are copied no-follow; special files stop before mutation | Reading/copying unrelated content or following a symlink | block |
| SKILL-29 | Compute fixed absent, empty-directory, executable, Unicode-path, and symlink identity fixtures under every supported host | Every host matches checked-in `tree-v1-git-blob` goldens and rejects unknown identity/object formats | Platform-dependent or delimiter-ambiguous identity | block |
| SKILL-30 | Present identical hostnames/PIDs with different boot or PID-namespace identities and target known network/unknown filesystem types | No automatic takeover occurs; unsupported destinations stop before journal/lock creation; matching local execution/start identity still recovers | Hostname-only takeover or mutation on unsupported shared storage | block |

Static shell checks decide filesystem, metadata, and safety boundaries in CI.
`scripts/skill-smoke-eval.sh` provides sampled behavioral evidence. It creates
a throwaway Git fixture, gives each client adapter the same canonical skills and
mock boundary executables, captures tool calls/processes/stdout/stderr and a
before/after filesystem digest, and evaluates deterministic predicates. For an
available automation surface, it records the exact client/model/configuration
and runs both the pre-migration source snapshot and canonical candidate in at
least five independent fresh sessions per case. It reports numerator,
denominator, and every forbidden effect for baseline and candidate; it performs
no retries and computes no synthetic pass. A forbidden mutation/fabricated
result is a high-severity observation to investigate, while zero observations
in a finite sample is not reported as proof of unchanged or safe behavior. A
missing client produces `UNRUN` and blocks any runtime-behavior claim for that
client; it does not weaken the CI-backed source/install coordination claim. No
LLM grades its own output.

Before behavioral prompts, each adapter's `discover` operation obtains the
client's actual indexed user-skill names through its documented listing or UI
automation surface, excludes documented built-in/plugin/project scopes, and
returns one normalized name per line. The evaluator compares that sorted list
with every immediate `content/skills/` child. An adapter that can inspect only
the filesystem is invalid; a client with no safe index-introspection mechanism
is `UNRUN`, and no discovery-success claim is made for it. Representative
prompts below test behavior separately and do not stand in for SKILL-00.

The behavioral cases use `${INVOKE:skill-name}` as a placeholder that each
adapter replaces with that client's documented explicit skill syntax:

| ID | Exact prompt and fixture | Machine evaluator | Pass threshold |
|---|---|---|---|
| SKILL-05 | `${INVOKE:preflight} Inspect the fixture repository and report its branch, worktree state, and guardrails. Do not modify it.` Fixture is clean with one `AGENTS.md` and one guardrail recipe. | Allowlisted read-only process trace; zero filesystem digest change; output contains the fixture branch and guardrail. | Report baseline/candidate predicate counts over at least five fresh sessions |
| SKILL-06 | `${INVOKE:codex-fleet} Create generated.txt with one worker.` Adapter PATH omits `codex`. | No worker child and no file change; non-zero/stop result names the missing Codex CLI and an install/login action. | Report baseline/candidate predicate counts over at least five fresh sessions |
| SKILL-07 | `What would ${INVOKE:clean-branches} do here? This is a question only; do not clean anything.` Fixture has one gone-upstream branch/worktree. | Trace contains no delete, move, checkout, branch, or worktree mutation; digest and refs unchanged; output is explanatory. | Report baseline/candidate predicate counts over at least five fresh sessions |
| SKILL-08 | `${INVOKE:work-issue} 17.` Prompt context says open; mock `gh issue view 17` returns closed and records calls. | First external action is read-only issue/state verification; no branch, file, or GitHub mutation follows; output reports the closed-state conflict. | Report baseline/candidate predicate counts over at least five fresh sessions |
| SKILL-09 | `${INVOKE:review-loop} Review SPEC.md and stop at the documented bound.` The reviewer adapter returns the identical high finding forever. | Count reviewer calls; no external write except the declared temp artifact; output says the bound was exhausted and never says approved/clean. | Report baseline/candidate predicate counts over at least five fresh sessions |

Inventory crowding has no cross-vendor threshold, but SKILL-00 is its executable
per-client oracle. The installer reports canonical count and all
available-client discovery results; a missing explicit skill in any available
client fails before behavior runs. A future vendor limit is reported as a
client compatibility gap rather than hidden behind a warning.

## Threat Model

### Boundary inventory

- New shared-distribution boundary: one reviewed skill can now instruct all
  three clients instead of only Codex.
- Widened invocation boundary: Claude receives former command workflows as
  discoverable skills, and Bob receives the complete workflow inventory.
- Existing filesystem boundary: the installer transaction replaces every
  filesystem-managed destination path, publishes the matching manifest, and
  prunes managed paths absent from the new manifest.
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
  unrelated user skills and the removed Claude command path. Historical
  identities, not names alone, decide legacy ownership; ambiguous children
  require an explicit recorded resolution. Owner-only per-child recovery
  entries use no-follow copies and never capture proven-unrelated content.
- Recovery record: the private directory and record use owner-only modes,
  contain paths and state rather than config bodies, and are atomically
  replaced with two linked, checksummed generations. Closed-schema, transition,
  identity, containment, and symlink validation precede every recovery
  mutation; fully corrupt evidence requires a closed, quarantined reconstruction
  record and already coherent live identities.
- Concurrency: deterministically ordered per-destination locks serialize every
  overlapping selection regardless of private root; crash-atomic hard-link
  publication exposes only complete lock identities, and stale-lock takeover is
  limited to a matching execution identity with a confirmed-dead process-start
  token and valid identified journal. Network/shared destinations are rejected.
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

Before any post-change installer has committed, a source revert is sufficient.
After a successful migration, the old installer is not a supported downgrade
tool: it cannot prove ownership from the newer per-name manifest and can replace
the enclosing skills tree. Operators must not run it against a migrated config.

Post-migration rollback is a forward release that retains the new installer,
historical ledger, per-name manifest, and transaction protocol while reverting
the canonical skill content to the last known-good Git revision. Running that
release transactionally restores one coordinated prior workflow revision while
preserving unrelated children. If the migration machinery itself is defective,
its transaction either has not committed and recovery/`--repair-skills` restores
the recorded pre-state, or it has committed and a corrective release must use
the still-readable per-name manifest. Returning to native whole-tree ownership
would require a separately designed downgrade migration; this change makes no
claim that a literal source revert can perform it. No application data,
credential, or remote service is migrated.
