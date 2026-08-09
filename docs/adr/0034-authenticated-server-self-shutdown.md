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

The server process owns publication. After both its user listener and dedicated loopback control
listener have bound, but before it emits readiness, it atomically installs owner-only active-server
metadata. A publication failure closes both listeners and exits without reporting startup success.
The authoritative record lives at
`$HOME/.local/state/superpowers/brainstorm/<project-key>.json`, independent of XDG environment.
`HOME` must be non-empty and absolute and remain invariant across a persistent lifecycle; otherwise
the helper fails with parseable JSON before state access. Existing `HOME`, `.local`, and `state`
ancestry must be effective-user-owned, non-symlink directories without group/world write. The
application-owned `superpowers` and `brainstorm` directories must be effective-user-owned,
non-symlink directories at exactly `0700`, creating them at that mode when absent.
`<project-key>` is the lowercase SHA-256 digest of the canonical project's UTF-8 path bytes.
Persistent mode rejects a canonical path that is not valid UTF-8 before reading or writing state,
returning parseable JSON. The shell sends the bounded canonical path as raw stdin bytes; the helper
applies a fatal UTF-8 decode before creating a string, rejects framing or trailing-byte violations,
then hashes. The record pairs the PID,
per-start server identifier, session directory, control port, and a separate random control
credential. It is installed before a session-local recovery copy so an interrupted publication
still leaves the live server discoverable. Ephemeral `/tmp` sessions retain only session-local
control metadata and do not publish the stable project record. This mode is gated by whether the
caller supplied `--project-dir`, not by classifying the resulting path; path aliases therefore
cannot turn an ephemeral invocation into a persistent one. `start-server.sh` canonicalizes
the project directory to its physical
absolute path after creating it; both scripts derive the stable record from that identity and the
session directory returned by start remains the stop command's input.
Both record copies use the same versioned schema and carry `project_key`; it is null for ephemeral
sessions. `stop-server.sh` uses a non-null key to address stable state and removes that record only
when its PID and server identifier still match the session copy.
Stable reads also require the record key to equal the requested filename key. Session reads require
`session_dir` to equal the canonical supplied session directory; ephemeral session records require
a null key. Any mismatch is stale recovery and sends no stop request.

One shipped Node helper owns metadata validation and the stop request for both
`start-server.sh` and `stop-server.sh`. It sends a bounded authenticated request containing the
expected PID and server identifier. The control listener accepts requests only from loopback,
compares the credential, PID, and identifier inside the target process, closes the user-facing
listener, acknowledges success only after that listener releases its port, and then exits itself.
An authenticated acknowledgement is successful shutdown and permits normal same-port replacement.
A timeout, refusal, or lost acknowledgement is not successful shutdown, but under the approved
recovery policy it still permits startup through the normal bind/fallback path after predecessor
metadata is handled as described below. Shell scripts never signal a PID from this metadata.
The complete stop attempt has one non-resetting monotonic deadline covering connect, request,
response, user-listener closure, and acknowledgement. Metadata and both wire directions have byte
caps enforced before parsing; the server bounds request receive time and destroys lingering user
connections before acknowledging port release.

Missing, malformed, stale, or unreachable metadata is removed when owned by the caller and is
treated as recoverable. An unreachable or unresponsive predecessor is not force-killed.

## Consequences

Replacement is portable across macOS and Linux without parsing process command lines or risking
a recycled PID. It also works when the user-facing server binds beyond loopback because control
uses a separate loopback listener. The private metadata becomes a versioned local contract. Its
directory remains mode `0700`, its record remains `0600`, and parsing and deadlines have fixed
bounds.
The control credential comes from 32 bytes of Node cryptographic randomness. Its generator is an
injectable internal function boundary solely so deterministic tests can prove the exact RNG call;
the CLI and metadata schema do not expose that seam.

An unresponsive predecessor can remain alive and force its successor onto a fallback port. This
is safer than signalling an identity the operating system cannot prove, and startup still
returns its normal parseable JSON. The added listener consumes one ephemeral loopback port per
running server. Continuing also replaces the ambiguous predecessor's stable record with the
successor's record, so later project starts cannot retry that predecessor; only its session-local
recovery copy remains usable when its session directory is known. This loss is the explicit cost
of the human-approved continue-without-force-kill policy.

Stable-record mutation has a single-writer prerequisite: callers do not overlap start, stop, or
delayed cleanup for the same project. The protocol keeps every stop identity-safe under a race,
but concurrent lifecycle writers can hide a server or remove a successor's record because the
filesystem offers no portable compare-and-delete primitive. Serializing the whole lifecycle
transaction would require a separate stale-lock recovery policy not authorized by this decision.

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

**Keep credential state project-local.** A shared or replaceable project ancestor can redirect a
check-then-publish sequence after validation. A user-private state root supplies the required
credential boundary without changing the public CLI.
