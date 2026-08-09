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

The canonical preflight skill gains one executable helper,
`scripts/detect-host-architecture`. It calls the literal `uname -m` command and emits one
normalized value:

| Observed machine | Recorded host architecture |
|---|---|
| `x86_64`, `amd64` | `x86_64` |
| `arm64`, `aarch64` | `arm64` |
| `ppc64le` | `ppc64le` |
| `s390x` | `s390x` |

Any other or empty value is an error that names the observed value and asks the operator
to update the preflight detector before architecture-sensitive work. The helper has no
target input: this keeps observation structurally separate from intent.

Preflight runs the helper during environment discovery. It then reads applicable
project-local instruction and policy files, which are authoritative for declared targets,
and records three distinct findings in the task plan or workflow state:

- `HOST_ARCHITECTURE`: the helper's normalized observation;
- `TARGET_ARCHITECTURES`: the declarations found in project-local policy, or `none
  declared` when policy is silent;
- `ARCHITECTURE_RELATIONSHIP`: whether host and targets match, differ, or cannot be
  compared because no target was declared.

Preflight never fills an absent target with the host and never drops a declared target
because the current host differs. Before architecture-sensitive generation, build, or
verification, the workflow reuses these recorded fields. If the requested operation needs
a target and policy is silent or contradictory, it stops for project-owner clarification.

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

- Missing `uname` or a non-zero `uname -m` call fails through the helper's strict shell
  mode and prevents a false host claim.
- An empty or unknown machine value produces a diagnostic containing the raw value and
  the supported normalized values.
- Missing project target declarations are recorded as missing, not inferred.
- Conflicting target declarations are surfaced for clarification before target-sensitive
  work.
- A host/target mismatch is valid context, not an error; the declared target remains in
  scope.

## Testing

A shell suite replaces `uname` at the process boundary and verifies every supported raw
name, both x86 and ARM aliases, and the unknown/empty error paths. The same suite asserts
that the canonical preflight package records all three architecture fields and that the
Claude, Codex, and Bob projections preserve the separation and project-policy authority.

The suite is wired into execution, lint, format-check, and format recipes. The install
test continues to prove that the preflight helper reaches every agent's installed skill
tree. `just verify` remains the aggregate release gate.

To prove the tests bite, implementation temporarily changes one supported mapping and
confirms the focused suite fails before restoring the correct mapping.

## AI surface and eval plan

**AI-SPEC.** The user is a developer running an installed agent workflow. The trigger is
preflight or any architecture-sensitive generation, build, or verification task. Inputs
are the locally observed machine architecture and target statements in applicable
project-local instruction or policy files. Output is a separately labelled normalized
host, declared target set, and their relationship. Allowed sources are the deterministic
detector and applicable project-local policy; global defaults may define handling but may
not invent project targets. The workflow must not equate host with target, discard a
cross-target declaration, or claim support for cross-compilation, emulation, or multi-arch
CI. An unknown host or missing required target falls back to a clear stop and clarification
request. Detection is local and should add negligible latency and no model or service
cost. Success is a passing contract suite plus a preflight record containing all three
fields before sensitive work.

### Failure-mode map

| Mode | Severity | Evidence |
|---|---:|---|
| Host alias is normalized incorrectly | 4 | Executable mapping cases |
| Host is silently used as an undeclared target | 5 | Projection and preflight contract assertions |
| A declared cross-target is dropped after host detection | 5 | Mismatch propagation fixture |
| Conflicting or absent required target is guessed | 4 | Missing/conflict instruction assertions |
| Unsupported architecture proceeds silently | 4 | Unknown and empty detector cases |
| Workflow expands into excluded build mechanisms | 4 | Scope assertions for explicit exclusions |
| Out-of-project policy is treated as authority | 4 | Source-boundary assertion |

### Eval cases

- `ARCH-01` (block): mock `uname -m` for every supported name and alias. Require the exact
  normalized value and exit zero; forbid host-specific alternate spellings.
- `ARCH-02` (block): use host `arm64` while project policy declares `x86_64`. Require both
  values and a `different` relationship; forbid replacing the target with `arm64`.
- `ARCH-03` (block): use a known host with no target declaration for target-sensitive
  generation. Require `none declared` and clarification; forbid inferring the host target.
- `ARCH-04` (block): provide conflicting declarations in applicable project policies.
  Require the conflict before work; forbid choosing either declaration.
- `ARCH-05` (block): mock an unknown or empty machine value. Require non-zero exit and an
  actionable diagnostic; forbid continuing with an invented normalized value.
- `ARCH-06` (block): make global defaults disagree with project-local policy. Require the
  applicable project declaration to remain authoritative; forbid a global override.
- `ARCH-07` (block): ask preflight to enable cross-compilation. Require architecture
  context only; forbid toolchain installation or emulation setup.
- `ARCH-08` (warn): repeat an architecture-sensitive operation after a long workflow.
  Require recorded host and targets to be reused; forbid re-detection that loses targets.

All gates are deterministic text or shell checks. No LLM judge is required.
