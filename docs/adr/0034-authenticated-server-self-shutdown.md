# 0034 — Authenticate server replacement inside the server process

## Status

Accepted (2026-08-08)

## Context

Persistent brainstorm sessions need to stop a predecessor before starting its replacement.
The current PID file is per-session and therefore cannot locate that predecessor. Reusing a
PID alone is unsafe, while the per-start marker in process arguments is not a sound identity
boundary on macOS because `ps` flattens argument boundaries. Any shell-side
verify-then-signal sequence also races process exit and PID reuse.

## Decision

Each persistent project records owner-only active-server metadata only after both the user
server and a dedicated loopback control listener have started. The metadata pairs the PID,
per-start server identifier, session directory, control port, and a separate random control
credential. Ephemeral `/tmp` sessions retain session-local control metadata but do not publish
the stable project record. `start-server.sh` canonicalizes the project directory to its physical
absolute path after creating it; both scripts derive the stable record from that identity and the
session directory returned by start remains the stop command's input.

One shipped Node helper owns metadata validation and the stop request for both
`start-server.sh` and `stop-server.sh`. It sends a bounded authenticated request containing the
expected PID and server identifier. The control listener accepts requests only from loopback,
compares the credential, PID, and identifier inside the target process, closes the user-facing
listener, acknowledges success only after that listener releases its port, and then exits itself.
The helper starts a successor only after that authenticated acknowledgement. A timeout or lost
connection is stale recovery, never successful shutdown. Shell scripts never signal a PID from
this metadata.

Missing, malformed, stale, or unreachable metadata is removed when owned by the caller and is
treated as recoverable. An unreachable or unresponsive predecessor is not force-killed.

## Consequences

Replacement is portable across macOS and Linux without parsing process command lines or risking
a recycled PID. It also works when the user-facing server binds beyond loopback because control
uses a separate loopback listener. The private metadata becomes a versioned local contract and
must remain mode `0600`; the helper and server must bound parsing, request size, and timeouts.

An unresponsive predecessor can remain alive and force its successor onto a fallback port. This
is safer than signalling an identity the operating system cannot prove, and startup still
returns its normal parseable JSON. The added listener consumes one ephemeral loopback port per
running server.

The supported start path has a single-writer prerequisite: callers do not start the same project
concurrently. The protocol keeps every stop identity-safe under a race, but two concurrent starts
can both succeed and the last metadata publication can hide the other server. Serializing the
whole stop/start/publish transaction would require a separate stale-lock recovery policy not
authorized by this decision.

## Considered & rejected

**OS process birth tokens.** Linux exposes a precise start token in `/proc`, but macOS `ps`
offers a weaker timestamp and neither platform makes a shell verify-then-signal sequence atomic.

**Unix-domain control sockets.** They provide a strong local boundary, but portable Windows
named-pipe naming and stale-socket cleanup are substantially larger than a loopback listener.

**Keep the current process-argument marker.** macOS loses argument boundaries and a PID may exit
after validation, so this cannot establish the required signal safety.

**Put shutdown on the user-facing listener.** A listener bound to a specific non-loopback address
cannot also accept a loopback-only request, while accepting the request on that address exposes a
control route beyond localhost. A separate loopback listener preserves all supported bind modes.

**Do nothing.** The existing session-local PID cannot locate a predecessor, so persistent restarts
continue leaking servers and do not meet the required replacement behavior.
