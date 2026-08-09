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
version-1 JSON metadata contains `version`, `pid`, `server_id`, `session_dir`, `project_key`,
`control_port`, and `control_token`. `project_key` is the 64-character digest for persistent
sessions and null for ephemeral sessions. Metadata is at most 16 KiB. It opens records without
following symlinks and validates the same descriptor it reads. It accepts only a regular,
effective-user-owned, owner-readable file with no group or world permissions, an absolute UTF-8
session path of at most 4096 bytes, PID 1..2147483647, port 1024..65535, an ASCII server ID of
32..64 characters, and an exact 64-character lowercase hexadecimal credential. Malformed input
produces a categorized JSON result and never throws raw output at shell callers.
Stable reads require `project_key` to match the requested filename key. Session reads require
`session_dir` to match the canonical input directory, and ephemeral records require a null key.
Mismatch sends no request. Persistent start treats it as recoverable stale state; session stop
treats a present mismatch as unverifiable and preserves it.

For persistent starts, the authoritative path is
`$HOME/.local/state/superpowers/brainstorm/<sha256>.json`, regardless of `XDG_STATE_HOME`.
`HOME` must be non-empty and absolute. Invariance is a caller prerequisite: changing it makes prior
records undiscoverable and cannot be diagnosed from the new root. `HOME`, `.local`, and
`state` must be effective-user-owned non-symlink directories without group/world write. Missing
`.local` and `state` components are created one at a time at 0700, then immediately validated;
`superpowers` and `brainstorm` must additionally be exactly mode 0700.
If creation or writing is denied by the current sandbox, persistent mode returns one JSON error
that names `$HOME/.local/state/superpowers/brainstorm` and instructs the operator to authorize or
write-enable it. It never attempts or requests escalation itself.
`<sha256>` is the lowercase SHA-256 digest of the canonical project's UTF-8 path bytes. The shell
pipes one EOF-delimited raw value of at most 4096 bytes to the helper. Newlines are data; NUL,
overflow, or fatal UTF-8 decoding fails before hashing or state access and returns parseable JSON.
The helper creates `superpowers`
and `brainstorm` at mode 0700, rejects
symlinks, wrong ownership, or group/world write on those components, and atomically installs both
records at 0600. Session-local recovery metadata stays under the project. Ephemeral mode never
computes this path.

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
Before awaiting closure, the first valid request atomically changes an in-process lifecycle value
from `running` to `stopping`. Later valid requests return a bounded `stopping` response and never
repeat listener closure or exit scheduling.

The server process owns publication. `start-server.sh` passes the canonical paths and prepared
metadata inputs, but the server emits no `server-started` line until both listeners have bound and
publication completes. With `--project-dir`, the server atomically installs the authoritative
user-state record first, then installs an identical session-local recovery
copy. A crash between those renames leaves the live server discoverable by the next start.
Ephemeral mode is selected solely by the absence of `--project-dir`; it installs only the
session-local copy and never infers persistence from the canonical path. Failure before the stable
commit or during
the ephemeral copy closes both listeners and exits without readiness; persistent failure after the
stable commit preserves that authoritative recovery record for stale recovery on the next start.

Each rename is atomic; the pair is deliberately not described as a transaction. If publication
fails, the server removes its prepared files, closes both listeners, and exits after emitting one
parseable error object for the launcher to return. If the authoritative record was already
installed, it remains as stale input for the next invocation rather than risking deletion of a
newer record. No launcher-side authenticated rollback runs against a server that has failed
publication.

Before starting a persistent successor, `start-server.sh` invokes the shared helper in replacement
mode on the stable metadata. `stopped`, `not_running`, `stale`, malformed, empty, missing, timeout,
and connection failures are all recoverable. The helper removes only the stable path the caller
explicitly supplied; the successor then starts normally.

`stop-server.sh <session_dir>` invokes the same parser, validator, liveness probe, and authenticated
request in session-stop mode. A missing session record maps to the existing
`{"status":"not_running"}` success. An authenticated acknowledgement maps to
`{"status":"stopped"}` success. If a request cannot complete and the PID is confirmed absent,
the helper removes the session record and maps to `{"status":"stale_pid"}` success. A present but
empty, malformed, unreadable, mismatched, or otherwise unauthenticated record maps to the existing
`{"status":"failed","error":"..."}` shape and a nonzero exit whenever its PID is live or
liveness cannot be established. That error names the metadata path and PID when available, says
identity could not be verified, and says state was preserved. It preserves the session record and
any addressed stable record and sends no request when parsing or validation failed.

After a successful stop, persistent cleanup conditionally removes the stable record addressed by
`project_key` only when its PID and server ID match the stopped session. This is stale-state
hygiene, not an atomic compare-and-delete guarantee: stable-record mutations have the same
single-writer prerequisite, so callers do not overlap start, stop, or delayed cleanup for one
project.

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
stdout remains exactly the new server's connection JSON. `stop-server.sh` forwards the mapped
public result and preserves its existing status vocabulary. No stale or failure path invokes a
signal; the helper uses PID liveness only to distinguish confirmed absence from unverifiable state.
The client permits 500 ms to connect and one non-resetting 3000 ms wall-clock deadline for the
whole request and response; response JSON is capped at 4096 bytes. The endpoint caps request bodies
at 1024 bytes and the full receive interval at 1000 ms. Crossing a bound closes the socket and
returns categorized JSON without echoing input.

## Threat model

### Boundary inventory and actors

- New boundary: two credential-bearing metadata copies enter the helper. The authoritative copy is
  under the owner-private state root; the recovery copy is under the project. A different local
  account is untrusted. Same-account processes are trusted because they can already replace the
  scripts and read owner files.
- New boundary: HTTP reaches the control listener. Browser pages, remote network peers, and other
  local accounts are untrusted.
- Existing widened boundary: lifecycle values enter `server.cjs` through environment/arguments.
  The launching script is trusted; malformed values must fail closed.

### Controls

- The authoritative credential-bearing record lives under the owner-private state root. Its helper
  validates both application-owned directories without following symlinks and requires effective-
  user ownership and mode 0700. Both it and the project-local recovery record are atomically
  installed at 0600 and accepted only when regular, effective-user-owned, owner-readable, and free
  of group or world permissions. Reads open without following symlinks and validate and bound the
  opened descriptor, so path substitution cannot redirect the read. Project-local replacement can
  deny service or destroy recovery, but cannot disclose a valid token or authenticate shutdown.
  The helper rejects oversized files, unknown versions, malformed values, and session mismatches.
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
active record in the supported serial path. For missing session metadata, assert `not_running` and
success. For a confirmed-absent PID, assert `stale_pid` and cleanup. For unreadable, empty,
malformed, mismatched, live-unreachable, and indeterminate-liveness session metadata, assert an
actionable `failed` result, nonzero exit, no request or signal, and preservation of both metadata
copies. Add recovery-copy ownership, mode, symlink substitution, and replacement cases proving an
untrusted project writer can cause denial or recovery loss but cannot disclose a token or
authenticate shutdown. Add boundary cases at 16 KiB metadata, 4096-byte
paths/responses, 1024-byte requests, PID/port/ID/token limits, unknown versions, type-invalid and
mismatched-session metadata. Test the non-resetting 3000 ms client and 1000 ms receive deadlines
with peers that drip bytes. Cover listener address and loopback validation. Add state-root cases for
XDG-independence, deterministic SHA-256 keys, invalid UTF-8 path rejection, symlinked components,
wrong ownership where the host permits it, and group/world-writable modes; each fails before
credential publication.
Cover empty/relative HOME, missing `.local` and `state` bootstrap at 0700, changed-HOME
undiscoverability as a documented prerequisite, embedded-newline identity, and rejection at NUL,
invalid UTF-8, and 4097 bytes.
Simulate permission denial at each state-root component and assert nonzero exit plus one parseable
JSON error containing the fixed directory and write-enable action, with no state or server created.
Inject a crash after stable installation but before session-copy installation and prove the next
start discovers and stops that server. Fail each installation and assert the server closes both
listeners, removes prepared files, and emits parseable JSON; where the stable record was installed,
the next start consumes it safely as stale. Substitute a deterministic `randomBytes` function
and assert it is called for exactly 32 bytes whose exact returned value becomes lowercase hex;
separate format tests assert 64 hex characters. Mutation proof must demonstrate that bypassing the
RNG boundary, server-side identity validation, or predecessor stop makes the tests fail. Run
`just verify` as the repository gate.

Exercise ephemeral mode through a physical `/tmp` alias and prove no stable record is written;
persistence is determined by option state, never by a path-prefix check.

Send two valid authenticated stop requests before user-listener closure completes and prove only
one lifecycle transition occurs; the retry receives deterministic `stopping` JSON without a raw
exception or second close.
