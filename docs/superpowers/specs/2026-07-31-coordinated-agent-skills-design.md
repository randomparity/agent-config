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
- Claude, Codex, and Bob installs receive byte-identical skill trees.
- A contributor cannot add any invocable workflow artifact under an agent-native
  tree without failing repository verification.
- Existing installs remove manifest-managed command copies and replace their
  managed skill tree on reinstall without touching unmanaged runtime state.
- An unmanaged legacy Claude command that collides with a canonical skill stops
  installation with the collision name and a recovery action.
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

The existing manifest mechanism already owns destination-relative paths. On the
first reinstall after this change, `commands` disappears from Claude's new
manifest and is backed up and pruned by the existing managed-path rules. The
`skills` entry remains managed and is replaced only when its canonical payload
differs. Unmanaged files outside those paths are unchanged.

Before installing Claude, inspect an existing `commands/` directory for command
filenames that match canonical skill names. If the old manifest owns `commands`,
normal backup and pruning handles it. If it does not, stop and name the collision
instead of deleting user content. Non-colliding unmanaged commands remain
outside the repository-managed workflow namespace. The selected client's entire
user-level `skills/` path remains managed, backed up, and replaced as it is
today. Project, enterprise, and plugin scopes are not modified.

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
7. rejects absolute supported-agent config-root references in canonical skills.

`just verify` invokes `skills-check`, making it part of both hooks and CI. The
guard uses existing shell tools only.

`install-test.sh` compares the complete canonical tree against all three
temporary destination trees with `diff -qr`. It also seeds stale managed Claude
commands before install and verifies they are pruned while unrelated runtime
state survives. Representative assertions remain for discoverable skill names,
including `work-issue` in Bob, so failures point to user-visible behavior before
the full-tree comparison provides exhaustive coverage.

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
beyond loading the same skill content. Success is byte-identical installation,
correct discovery metadata, preserved direct invocation, and unchanged workflow
guardrails on each available client.

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
| Large skill inventory crowds discovery metadata | 3 | Inventory count reported; activation quality remains a runtime observation |

### Eval cases

| ID | Input and setup | Observable pass traits | Forbidden traits | Gate |
|---|---|---|---|---|
| SKILL-01 | Install all agents into empty temp roots | Every root equals `content/skills/`; Bob contains `work-issue` | Missing or extra workflow | block |
| SKILL-02 | Seed managed Claude `commands/` and unrelated runtime state, then reinstall | Commands are backed up/pruned; runtime state remains | Unmanaged deletion | block |
| SKILL-03 | Add a native skill fixture or malformed canonical frontmatter | `skills-check` fails and names the path | Silent acceptance | block |
| SKILL-04 | Canonical skill references `~/.codex` as its installed root | `skills-check` fails | Client-root coupling | block |
| SKILL-05 | Invoke a safe read-only skill in each locally available client | Client discovers the skill and follows its opening gate | Wrong skill or missing resource | warn when client unavailable |
| SKILL-06 | Ask for a workflow whose required client capability is absent | Skill stops and names the missing capability | Pretended tool result or bypass | block in content review |
| SKILL-07 | Ambiguous request resembling a mutating workflow | Skill asks/limits itself according to its explicit trigger | External write without authority | block in content review |
| SKILL-08 | Skill encounters stale or conflicting repository/GitHub evidence | Workflow verifies source state and reports conflict | Treating remembered state as fact | block in content review |
| SKILL-09 | Workflow would fan out or loop beyond its documented cap | Existing cap and stop contract remain present | Unbounded worker or review loop | block in content review |
| SKILL-10 | Unmanaged Claude command has a canonical skill name | Install fails before replacement and names the collision | Silent deletion or ambiguous invocation | block |

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
  trees and prunes paths absent from the new manifest.
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
  manifest-only pruning controls remain unchanged; regression tests cover the
  removed Claude command path.
- External actions: each workflow's current authorization and verification
  gates remain part of the compatibility review. Canonicalization does not
  widen GitHub token scopes or shell permissions.

### Out of scope

- A malicious maintainer-approved skill can instruct an agent to take harmful
  actions; code review and client approvals are the trust boundary for source
  changes.
- Clients may interpret portable prose differently. Static verification proves
  package identity, not identical model behavior.
- Vendor-specific discovery limits may omit metadata from a very large skill
  inventory. This change reports the inventory and preserves explicit
  invocation; redesigning client discovery is vendor-owned.

## Rollback

Reverting the change restores native source trees and installer entries. The
next install uses the existing drift-backup mechanism before replacing managed
paths. No persisted application data, schema, credential, or remote service is
migrated.
