# Overlay Protected Keys Design

## External authority

Issue #110 reports that `install.sh` merges a private `settings.overlay.json` into a public base
settings file with `jq -s '.[0] * .[1]'`, and that jq's `*` replaces arrays rather than merging
them. An overlay defining `hooks.PreToolUse` therefore drops every hook the base defines, silently
and without a failing gate. The issue asks for a deployed-artifact check that fails when the
settings Claude Code actually loads is missing a hook the base file defines.

The campaign orchestrator's dispatch brief adds: the same reasoning must apply to all three
`merge_json_settings` call sites; `install-test.sh` must assert against a deployed settings file
and the assertion must fail if the fix is reverted; the documented `permissions.allow` overlay in
`examples/hosts/example-host/` must keep working; the decision is recorded as ADR 0043; `README.md`
must document the actual contract; and `just verify` must pass bare.

Excluded: the `settings.base.json` deny entries (issue #111, deferred by operator decision);
`scripts/claude-settings-hooks-test.sh` beyond the overlay clause in its header comment (#112 and
#113 own other regions of that file); `merge_toml_config` and the Codex TOML overlay, which are
flagged but not changed; and merging the pull request, which the orchestrator owns. The frozen
scope is issue #110 plus `work-110-overlay-merge-20260810`; no design-changing ambiguity remains.

## Approaches

The chosen approach rejects an overlay that would erase a base value it does not name, and derives
the protected set from the base file at merge time rather than from a list in `install.sh`. It is
recorded in [ADR 0043](../../adr/0043-overlays-may-not-replace-a-base-array.md), which also carries
the rejected alternatives: array union (wrong for an order-bearing list such as `hooks.PreToolUse`),
reassert-after-merge (trades one silent failure for another), a hardcoded protected-key list
(protects the values someone remembered, not the ones that exist), containment instead of equality,
and warn-and-continue.

## Merge contract

`merge_json_settings(base, overlay, output)` behaves as follows.

| Input | Behavior |
|---|---|
| No overlay file | Copy the base through `jq '.'`; report that no overlay was applied. Unchanged. |
| Overlay that adds keys, or overrides scalars and object members | Merge with `.[0] * .[1]`; report that the overlay was applied. Unchanged. |
| Overlay that adds an array at a path the base does not define, or replaces an empty base container (`[]` or `{}`) | Merged and kept. This is what `permissions.allow` in the example host does. |
| Overlay that writes a path the base holds as a non-empty array — **extending it included** — or turns a base object into a non-object, by naming its path or by replacing an ancestor | **Abort the install**, naming the overlay file and every base path the merge would not have preserved. Write no output. |

The protected set is computed from the base on each merge, in two clauses: every path whose value
is a **non-empty array** must be identical in the merged output, and every path whose value is an
**object** must still hold an object there. The second clause is what stops `"env": null` from
dropping the base's whole `env` subtree while the array check still passes. Scalars and empty base
containers are unprotected, because replacing either erases nothing the overlay author did not
name; `agents/bob/shared/settings.base.json` (`{}`) and `mcpServers` in `agents/bob/shared/mcp.json`
(`{}`) sit on that exemption today.

The check is expressed over the merge output rather than over the overlay's shape: after computing
`.[0] * .[1]` into a temporary file, each protected base path is compared against the result. One
comparison covers every route to the loss — naming the path, and replacing any ancestor of it —
without restating jq's recursion rules.

All three call sites obtain this from the shared function: the Claude settings overlay, the Bob
settings overlay, and the Bob MCP overlay. Bob's two base files contain no arrays today, so the
check is satisfied vacuously there; it is not conditioned on the agent.

Failure exits non-zero before any file is deployed *for that agent*, because a partially guarded
settings file gives the operator no signal that the tree they are working in is unguarded. Under
`--agent all` the agents installed earlier in the sequence stay deployed, each from a base or a
valid overlay; the guarantee is per-agent rather than per-run. The message names the operation, the
overlay path, and each offending base path, and states that the currently deployed settings file is
unchanged and may already be missing those values — a host that already installed a clobbering
overlay stays unguarded until the overlay is fixed, and the abort lengthens rather than shortens
that window.

## Threat model

**Boundary inventory.** The design adds no boundary and widens none. One existing boundary is
relevant: `install.sh` reads a private overlay file from
`${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/hosts/<host>/<agent>/` — a path outside
this repository, supplied by the operator — parses it as JSON, and merges it into a file that
configures Claude Code's own permission and hook enforcement. That boundary exists today; this
change adds a check on it.

**Actor model.** The operator running `install.sh` is trusted; the overlay is their own file on
their own machine, and anyone who can write it can equally write `~/.claude/settings.json`
directly. The untrusted party is not a person but a *mistake*: an overlay written by an operator,
or generated by an agent, that names `hooks.PreToolUse` intending to add and in fact removing. The
design places its trust in the base file being the authority on guardrails and the overlay being
host-specific decoration, and this change is what makes that trust checkable instead of assumed.

**Control per boundary.** The overlay merge is governed by the two-clause preservation comparison
above, which is a bound (what the overlay may not do) rather than a validation of content. It fails
closed: on a mismatch nothing is deployed for that agent and the install exits non-zero. It does
not repair an already-deployed unguarded file — see ADR 0043's consequences. On failure it leaks the
overlay's filesystem path and the JSON paths of the arrays involved — both already known to the
operator reading the message, and neither containing overlay values, so a secret held in the
overlay is not echoed. JSON well-formedness is delegated to `jq`, which already fails the install
on a malformed overlay.

**Explicitly out of scope.** An operator who edits the deployed `~/.claude/settings.json` after
install, or who edits the base file itself, is not addressed — the installer's guarantee is about
what it writes, not what happens afterward, and the manifest/prune mechanism already reports drift
on the next run. Overlay *content* is not validated: an overlay may still add a `permissions.allow`
entry that widens what Claude Code may do, which is the documented purpose of the mechanism. The
Codex TOML overlay is not covered; `merge_toml_config` concatenates sections rather than merging
JSON, so it has a different failure mode, and it is flagged rather than fixed here. Nothing here
defends against a hostile local user, who has strictly easier paths.

## Verification

Two assertions, both against a deployed artifact rather than the in-repo base file.

1. **Survival.** After the existing `install-test.sh` run with its benign overlay, the deployed
   `$CLAUDE_CONFIG_DIR/settings.json` must hold `hooks` and `permissions.deny` identical to
   `agents/claude/shared/settings.base.json`. This pins the property the issue names — the settings
   Claude Code actually loads still carries every hook the base defines — and it also covers a
   future reassert-style regression.

2. **Rejection.** A second install run, in its own temporary tree, with an overlay whose
   `hooks.PreToolUse` is a one-element array, must fail: `install.sh` exits non-zero and its
   message names the offending path. This is the assertion that fails if the fix is reverted —
   against current behavior the install succeeds and the deployed file silently carries one hook
   instead of five. The run must also leave no deployed `settings.json` behind, which is what
   distinguishes an abort from a partial install; Claude is the first agent `--agent all`
   installs, so for this fixture nothing is deployed at all.

3. **Object erasure.** A third install run with an overlay whose `env` is `null` must fail the same
   way. This is the clause the array check alone does not cover, and against unmodified `install.sh`
   it deploys a settings file with the base's whole `env` subtree gone.

The rejection assertions are the ones that bite, so they are written first and observed failing
against unmodified `install.sh` before the fix lands.

`scripts/claude-settings-hooks-test.sh` keeps reading hooks out of the base file; its header
comment stops claiming that overlays merely "must" leave hooks alone and states that the installer
now enforces it, pointing at ADR 0043. No other region of that file is touched.

`README.md`'s Private Overlays section gains the contract in the table above, stated in the two
sentences an operator needs: an overlay may add and may override scalars and object members, and an
overlay that replaces an array the base defines fails the install.

The guardrail is `just verify`, run bare.
