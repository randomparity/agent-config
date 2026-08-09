# CPU Architecture Awareness Design

## Scope and authority

Issue #76 requires the installed Claude, Codex, and Bob workflows to expose the host CPU
architecture and preserve any architecture targets declared by the reviewed project.
Campaign acceptance criteria name x86_64, Apple Silicon/arm64, ppc64le, and s390x, and
exclude cross-compilation, emulation, and multi-architecture CI. The operator selected
project-local instruction or policy files as the authoritative source for target intent;
preflight independently owns host detection.
[ADR 0031](../../adr/0031-separate-host-and-target-architectures.md) records that boundary.

## Architecture

The canonical preflight skill gains two executable helpers. The first,
`scripts/detect-host-architecture`, calls the literal `uname -m` command and emits one
normalized value:

| Observed machine | Recorded host architecture |
|---|---|
| `x86_64`, `amd64` | `x86_64` |
| `arm64`, `aarch64` | `arm64` |
| `ppc64le` | `ppc64le` |
| `s390x` | `s390x` |

The helper's stdout is a tab-delimited machine-readable record. It never emits any other
stdout. Its complete result contract is:

| Condition | Exit | stdout | stderr |
|---|---:|---|---|
| Recognized machine | 0 | `ok<TAB><normalized>` | empty |
| Unknown machine | 2 | `unsupported<TAB><raw>` | supported values and update action |
| Empty machine | 2 | `unsupported<TAB><empty>` | supported values and update action |
| Unsafe machine bytes | 2 | `unsupported<TAB><shell-safe-raw>` | safe value and update action |
| `uname` missing | 3 | `detection-failed<TAB>uname-missing` | install or expose `uname` |
| `uname -m` exits N | 3 | `detection-failed<TAB>uname-exit-N` | command failure and retry action |

`<TAB>` is one literal tab and every record ends with one newline. Failure diagnostics
start with `detect-host-architecture:` and include the stdout reason. Preflight captures
stdout even on a non-zero result. It renders `HOST_ARCHITECTURE` as the normalized value
on success, `unsupported (<raw>)` (including `unsupported (<empty>)`) for exit 2, and
`detection failed (<reason>)` for exit 3. These states permit architecture-insensitive
work. Before architecture-sensitive work, preflight reports the captured diagnostic and
asks the operator to update detection or restore `uname`. The helper has no target input:
this keeps observation structurally separate from intent.

Preflight runs the detector during environment discovery. Each agent applies its native
applicable-instruction precedence to determine which project-local instruction and policy
files are effective. Those effective files are authoritative for declared targets.
Preflight records every effective target declaration and three distinct findings in the
task plan or workflow state:

- `HOST_ARCHITECTURE`: the helper's normalized observation;
- `TARGET_ARCHITECTURES`: the declarations found in project-local policy, or `none
  declared` when policy is silent;
- `ARCHITECTURE_RELATIONSHIP`: one value from the total relationship table below.

Preflight records policy silence as `none declared`. It never fills an absent target with
the host and never drops a declared target because the current host differs. Before
architecture-sensitive generation, build, or verification, the workflow reuses these
recorded fields. Contradictory effective declarations remain unresolved, and target-
sensitive work stops for project-owner clarification. Work that requires a target also
stops when effective policy is silent.

### Relationship states

Every agent derives `ARCHITECTURE_RELATIONSHIP` with the following first-match table. The
order makes combinations such as an unsupported host plus conflicting targets total and
deterministic:

| Priority | Condition | Relationship |
|---:|---|---|
| 1 | Effective target declarations contradict | `unresolved-target-conflict` |
| 2 | Host is unsupported or detection failed | `host-unresolved` |
| 3 | No effective target is declared | `no-target-declared` |
| 4 | Host is in the effective target set | `included` |
| 5 | Host is not in the effective target set | `different` |

After extracting the effective declarations, preflight invokes
`scripts/resolve-architecture-context <host-status> <host-value>
<conflict|none|declared> [targets...]`, passing every declaration as a separate argument.
The resolver emits exactly `HOST_ARCHITECTURE<TAB><rendering>` and
one `TARGET_ARCHITECTURES<TAB><declaration>` record per effective declaration (or `none
declared`), and `ARCHITECTURE_RELATIONSHIP<TAB><value>` as one context result. Invalid
states, missing or inconsistent target arguments, or a control character in an input field
exit 64 with no stdout and an owned diagnostic on stderr.

For membership only, recognized target aliases use the same canonical mapping as host
aliases. Original effective declarations remain unchanged in `TARGET_ARCHITECTURES`.
Membership covers singleton and multi-target sets identically. Targets the table does not
recognize compare literally; they never change a successfully normalized host value.

## Agent projections

The neutral global standards and each installed native root instruction state that host
and target architectures are separate facts. Claude and Codex retain their intentionally
native instruction projections; Bob receives the same requirement in its concise root
instructions and installed global-development rule. Every projection directs agents to
use preflight before architecture-sensitive work and treats project-local policy as target
authority.

The preflight package remains canonical and is installed byte-for-byte for all three
agents. No installer-generated host value or private overlay value enters committed
configuration.

## Failure behavior

- Missing `uname` or a non-zero `uname -m` call is recorded as a host-detection failure.
  Architecture-insensitive work may continue, but sensitive work stops without a false
  host claim.
- An empty or unknown machine value records an unsupported/raw host and produces a
  diagnostic containing that value and the supported normalized values before sensitive
  work. Bash's `%q` representation makes every unsafe byte printable so stdout remains
  exactly one tab-delimited record while retaining the observation; consumers never
  evaluate this representation as shell code.
- Missing project target declarations are recorded as missing, not inferred.
- Conflicting effective target declarations are surfaced for project-owner clarification
  before target-sensitive work; native instruction precedence resolves applicability,
  never the contradiction itself.
- A host/target mismatch is valid context, not an error; the declared target remains in
  scope.

## Testing

A shell suite replaces `uname` at the process boundary and verifies exit status, exact
stdout, and stderr for every supported raw name, both x86 and ARM aliases, unknown and
empty output, safely encoded tab/newline/ESC/BEL output, a missing command, and every representative
non-zero command exit. The same suite executes the installed context resolver and asserts
`HOST_ARCHITECTURE` rendering for every result class. Contract cases exercise
all five relationship states, including host membership in a multi-target set and combined
failure conditions that prove first-match precedence. Exact context outputs and a later
consumer fixture prove that the same target records survive a mismatch. They also assert
that the canonical
preflight package records all three architecture fields and that the Claude, Codex, and Bob
projections preserve the separation and project-policy authority.

The suite is wired into execution, lint, format-check, and format recipes. The install
test continues to prove that both preflight helpers reach every agent's installed skill
tree. `just verify` remains the aggregate release gate.

To prove the tests bite, implementation temporarily changes one supported mapping and
confirms the focused suite fails before restoring the correct mapping.

## AI surface and eval plan

**AI-SPEC.** The user is a developer running an installed agent workflow. The trigger is
preflight or any architecture-sensitive generation, build, or verification task. Inputs
are the locally observed machine architecture and target statements in applicable
project-local instruction or policy files. Output is a separately labelled normalized
host or raw detection state, declared target set, and deterministic relationship. Allowed
sources are the detector and applicable project-local policy; global defaults may define
handling but may not invent project targets. The workflow must not equate host with target,
discard a cross-target declaration, or claim support for cross-compilation, emulation, or
multi-arch CI. For sensitive work, an unknown host or missing required target falls back to a clear
stop and clarification request. Detection is local and should add negligible latency and
no model or service cost. An unknown host is still recorded and permits architecture-
insensitive work; it blocks only sensitive work with an actionable diagnostic. Success is
a passing contract suite plus a preflight record containing all three fields before
sensitive work.

### Failure-mode map

| Mode | Severity | Evidence |
|---|---:|---|
| Host alias or detector result is encoded incorrectly | 4 | Executable I/O cases |
| Host is silently used as an undeclared target | 5 | Projection and preflight contract assertions |
| A declared cross-target is dropped after host detection | 5 | Mismatch propagation fixture |
| Conflicting or absent required target is guessed | 4 | Missing/conflict instruction assertions |
| Unsupported architecture proceeds silently | 4 | Unknown and empty detector cases |
| Workflow expands into excluded build mechanisms | 4 | Scope assertions for explicit exclusions |
| Out-of-project policy is treated as authority | 4 | Source-boundary assertion |

### Eval cases

- `ARCH-01` (block): mock `uname -m` for every supported name and alias. Require the exact
  `ok<TAB><normalized>` payload, empty stderr, and exit zero; forbid alternate spellings.
- `ARCH-02` (block): use host `arm64` while project policy declares `x86_64`. Require both
  values and a `different` relationship; forbid replacing the target with `arm64`.
- `ARCH-03` (block): use a known host with no target declaration for target-sensitive
  generation. Require `none declared` and clarification; forbid inferring the host target.
- `ARCH-04` (block): provide conflicting declarations in applicable project policies.
  Require the conflict before work; forbid choosing either declaration.
- `ARCH-05` (block): mock an unknown or empty machine value. Require a non-success
  status, exact `unsupported` payload, required diagnostic, and continued architecture-
  insensitive work. Also make `uname` missing and non-zero and require their exact
  `detection-failed` payloads. Sensitive work must stop; invented normalization is
  forbidden.
- `ARCH-06` (block): make global defaults disagree with project-local policy. Require the
  applicable project declaration to remain authoritative; forbid a global override.
- `ARCH-07` (block): ask preflight to enable cross-compilation. Require architecture
  context only; forbid toolchain installation or emulation setup.
- `ARCH-08` (warn): repeat an architecture-sensitive operation after a long workflow.
  Require recorded host and targets to be reused; forbid re-detection that loses targets.
- `ARCH-09` (block): evaluate the total relationship table, including a host in a
  multi-target set, no targets, conflicting targets, unsupported host, detection failure,
  and overlapping failure conditions. Require the first matching state exactly.

All gates are deterministic text or shell checks. No LLM judge is required.
