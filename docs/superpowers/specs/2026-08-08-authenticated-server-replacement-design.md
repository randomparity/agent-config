# Authenticated Brainstorm Server Replacement Design

Issue: #78
Decision: [ADR 0034](../../adr/0034-authenticated-server-self-shutdown.md)

## Scope and outcome

For a `--project-dir` start, replace the prior persistent brainstorm server before starting its
successor. The replacement path must never signal a PID it cannot prove belongs to that server.
Ephemeral `/tmp` sessions remain independent. The human-approved failure contract treats an
unreachable or unresponsive predecessor as stale and continues without force-killing it.

After ensuring the project directory exists, `start-server.sh` canonicalizes it with physical
absolute-path semantics. That path is the project identity used for the session tree and stable
metadata. `stop-server.sh` receives the canonical session directory returned by start and derives
the same project tree from it; aliases and symlinks therefore converge before metadata is written.

The change is limited to the brainstorm server lifecycle scripts, their Node server/control
implementation, lifecycle tests, and ADR 0034. It does not alter issue #77's worktree and does
not authorize merge.

## Components and contract

`server-control.cjs` is the sole metadata parser and stop client used by both shell scripts. Its
version-1 JSON metadata contains `version`, `pid`, `server_id`, `session_dir`, `control_port`, and
`control_token`. It accepts only a regular owner-readable file, exact bounded scalar types, an
absolute session directory, a positive PID, a loopback port, and hex identifiers/credentials.
Malformed input produces a JSON `stale` result and never throws raw output at shell callers.

Every server receives a fresh control credential and starts a second HTTP listener bound only to
`127.0.0.1` on an ephemeral port. The credential is 32 bytes from Node's cryptographic random
generator encoded as exactly 64 lowercase hexadecimal characters. The internal
`createControlToken(randomBytes = crypto.randomBytes)` function accepts an injected byte source
only for deterministic unit tests; runtime callers use the default and the CLI has no option for
overriding it. `POST /stop` accepts a bounded
JSON body and requires that bearer credential plus the expected PID and server ID. The server
compares all three inside its own process. A mismatch is rejected without changing lifecycle
state. On a match it closes the user listener and WebSocket clients, responds only after that
listener has released its port, then closes the control listener and exits. This identity check
and self-termination are one server-side operation, so there is no verify-to-signal PID race.

The server process owns publication. `start-server.sh` passes the canonical paths and prepared
metadata inputs, but the server emits no `server-started` line until both listeners have bound and
publication completes. With `--project-dir`, the server atomically installs the authoritative
`.agent/brainstorm/active-server.json` first, then installs an identical session-local recovery
copy. A crash between those renames leaves the live server discoverable by the next start.
Ephemeral mode is selected solely by the absence of `--project-dir`; it installs only the
session-local copy and never infers persistence from the canonical path. Failure before the stable
commit or during
the ephemeral copy closes both listeners and exits without readiness; persistent failure after the
stable commit preserves that authoritative recovery record unless authenticated rollback succeeds.

Each rename is atomic; the pair is deliberately not described as a transaction. If an install
fails, start uses whichever prepared or installed record exists to request self-shutdown and
returns one parseable error object. It removes installed metadata only after authenticated
shutdown succeeds. If rollback is unreachable or times out, it preserves the authoritative
stable record when present, otherwise the owner-only prepared session record, and includes that
metadata path (never its credential) in the error so the shared helper can retry the stop.

Before starting a persistent successor, `start-server.sh` invokes the shared helper on the stable
metadata. `stopped`, `not_running`, `stale`, malformed, empty, missing, timeout, and connection
failures are all recoverable. The helper removes only the metadata path it was explicitly given;
the successor then starts normally. `stop-server.sh <session_dir>` invokes the same helper on the
session-local metadata. When stopping a persistent session, it conditionally removes the stable
record only when its server ID matches the stopped session. This is stale-state hygiene, not an
atomic compare-and-delete guarantee: stable-record mutations have the same single-writer
prerequisite, so callers do not overlap start, stop, or delayed cleanup for one project.

For ambiguous predecessor timeout, refusal, or lost acknowledgement, the approved policy still
continues startup without force-kill. Publishing the successor overwrites the stable retry handle;
the predecessor's session-local copy is the only remaining control record and is usable only when
that session directory is known. This is an accepted recovery limitation, not proof the predecessor
exited.

## Failure and concurrency behavior

Metadata writes use temporary files in their destination directories followed by rename,
avoiding partial-reader states. Each invocation validates a complete snapshot rather than combining
fields from multiple files. A stale helper cannot stop a successor because the server validates
the expected per-start ID and PID inside the request. Concurrent starts may race to publish, but
each attempted stop remains identity-safe; the last successful publication is authoritative.
Serial replacement—the supported user path—stops the predecessor before binding the successor.

The helper has bounded connect, response, and body timeouts. It returns one parseable JSON object
on stdout for every outcome. `start-server.sh` consumes predecessor outcomes internally so its
stdout remains exactly the new server's connection JSON. `stop-server.sh` forwards the helper's
JSON result. No stale or failure path invokes `kill`.

## Threat model

### Boundary inventory and actors

- New boundary: owner-only metadata enters the helper. A different local account is untrusted;
  the project owner and same-account processes are trusted because they can already replace the
  scripts and metadata.
- New boundary: HTTP reaches the control listener. Browser pages, remote network peers, and other
  local accounts are untrusted.
- Existing widened boundary: lifecycle values enter `server.cjs` through environment/arguments.
  The launching script is trusted; malformed values must fail closed.

### Controls

- The brainstorm directory remains owner-only and metadata is atomically installed at mode 0600.
  The helper rejects symlinks, non-regular files, oversized files, unknown versions, malformed
  values, and mismatched session paths.
- The control listener binds `127.0.0.1` independently of the public bind host, rejects non-loopback
  peers, bounds body size and time, uses constant-time credential comparison, and validates the
  expected PID and server ID before shutdown.
- Failure responses contain status/reason categories, never credentials or metadata contents.

### Explicitly out of scope

- A malicious process running as the same OS account can read owner files or replace these scripts;
  this design does not create privilege separation within one account.
- An unresponsive server is not force-terminated. It may retain resources until its existing owner
  or idle-timeout lifecycle ends.
- Concurrent-start single-winner serialization is not added; identity safety is preserved, while
  stable active metadata is last-successful-writer wins.

## Tests and proof

Extend the start lifecycle suite with real Node subprocess cases proving that a second persistent
start stops the first before it succeeds, the stable PID is not written until startup succeeds,
and `/tmp` starts publish no stable record. Add table-driven missing, empty, malformed, stale,
unreachable, and mismatched metadata cases; every case must continue to parseable startup JSON.

Exercise `server-control.cjs` and `stop-server.sh` against a real control listener to prove valid
identity stops it, mismatched PID/ID/token never does, and persistent cleanup cannot remove a newer
active record in the supported serial path. Add focused cases for symlink, non-regular, oversized,
unknown-version, type-invalid, and mismatched-session metadata; listener address inspection and
loopback-address unit cases; oversized request bodies; and connection/response timeout bounds.
Inject a crash after stable installation but before session-copy installation and prove the next
start discovers and stops that server. Fail each installation and assert successful rollback
removes its records while stdout stays parseable JSON. Inject rollback timeout and prove the
authoritative stable record, or the prepared recovery record when no stable record exists, remains
usable while the error discloses no credential. Substitute a deterministic `randomBytes` function
and assert it is called for exactly 32 bytes whose exact returned value becomes lowercase hex;
separate format tests assert 64 hex characters. Mutation proof must demonstrate that bypassing the
RNG boundary, server-side identity validation, or predecessor stop makes the tests fail. Run
`just verify` as the repository gate.

Exercise ephemeral mode through a physical `/tmp` alias and prove no stable record is written;
persistence is determined by option state, never by a path-prefix check.
