# 0031 — Separate Host and Target Architectures

## Status

Proposed

## Context

The installed workflows run on x86_64, Apple Silicon, IBM POWER ppc64le, and IBM
s390x hosts. A host architecture is an observed execution fact, while a target
architecture is project intent: generated code may target a different machine, or
several machines, from the one running the agent. The existing global instructions ask
agents to detect the host before building but do not define normalized architecture
names or preserve separately declared targets.

The repository already installs one canonical preflight package for Claude, Codex, and
Bob. Project-local instruction and policy files already own project-specific constraints
and override global defaults.

## Decision

Preflight owns host detection and normalizes common machine names to `x86_64`, `arm64`,
`ppc64le`, or `s390x`. A helper beside the canonical preflight skill performs that
deterministic normalization. For an unsupported host it returns a non-success detection
status together with the raw machine value. Preflight records that unsupported/raw value
and continues architecture-insensitive work; only architecture-sensitive generation,
build, or verification stops with an actionable diagnostic.

Project-local instruction and policy files are authoritative for declared target
architectures. Each agent applies its native applicable-instruction precedence to decide
which project policy is effective. Preflight records every target declaration that
remains effective under that precedence. Contradictory effective declarations are
unresolved and stop target-sensitive work for project-owner clarification; silence is
recorded as `none declared`. Preflight never infers a target from the host or replaces a
declared target with the detected host.

The global Claude, Codex, and Bob projections state the same separation rule. Contract
tests exercise host normalization and assert that the canonical workflow and all native
projections carry the rule.

## Consequences

- Known host aliases have one portable spelling across all installed agents.
- Cross-target project intent survives even when it differs from the machine running the
  agent.
- Projects that need explicit targets must state them in their local instructions or
  policy; no new configuration format is introduced.
- An unrecognized host remains visible without blocking unrelated work, while
  architecture-sensitive work stops instead of silently assuming compatibility.
- This decision provides awareness only. Cross-compilation, emulation, and
  multi-architecture CI remain outside its scope.

## Considered & rejected

- Add a machine-readable project target configuration. Rejected because it creates a new
  schema and adoption surface when project-local policy already owns target intent.
- Store host and default targets in install-time private overlays. Rejected because host
  identity and project intent have different lifetimes, and overlay defaults can silently
  become stale or non-portable.
- Document architecture awareness without a deterministic detector. Rejected because
  aliases such as `aarch64` and `amd64` would remain agent-dependent and detection could
  not be behaviorally tested.
- Do nothing and rely on each build tool to detect architecture. Rejected because build
  tools observe the host or their own defaults, not necessarily the project's declared
  code-generation targets.
