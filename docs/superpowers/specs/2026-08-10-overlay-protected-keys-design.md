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
| Overlay that reproduces a base non-empty array **verbatim** | Merged and kept — the merged result is unchanged, so nothing is lost. It aborts at the next base change; see below. |
| Overlay whose merged result changes a base non-empty array (**extending it counts**), or leaves a non-object where the base held a **non-empty** object — whether by naming the path or by replacing an ancestor | **Abort the install**, naming the overlay file and every base path the merge would not have preserved. Write no output. |
| Overlay that is not one JSON object — a non-object value, two concatenated documents, a repeated key | Unchanged, and out of scope: these lose *overlay* content, not base values. Issue #125. |

The rule is normative over the **merged result**, never over the overlay's shape, in two clauses
computed from the base on each merge: every path whose value is a **non-empty array** must be
identical in the merged output, and every path whose value is a **non-empty object** must still
hold an object there. The second clause's unique contribution is the scalar-only objects — `env`
and `statusLine` — since any object with a protected array beneath it already fails the first
clause.

What that clause buys is precisely **whole-subtree erasure**, and no more: `"env": null` and
`"env": "x"` abort, while `{"env": {"DISABLE_TELEMETRY": "0"}}` merges cleanly and deploys, because
scalars are unprotected. An overlay can still re-enable the telemetry the base disables by naming
the variable; what it cannot do is drop all four privacy defaults at once without naming any of
them. `env` is not a guarded value, and the spec should not be read as making it one.

**Empty base containers are unprotected — arrays and objects alike, symmetrically** — because
replacing either erases nothing the overlay author did not name. Both clauses therefore carry
"non-empty". The one input that separates this from the alternative reading exists in-repo:
`agents/bob/shared/mcp.json` is `{"mcpServers": {}}`, so an overlay of `{"mcpServers": null}`
installs rather than aborting. Objects are where the exemption bites today (Bob's two `{}` files);
for arrays it has no in-repo instance at all, so verification constructs one.

Because the rule is over the result and not the shape, an overlay reproducing a base array verbatim
passes today and aborts the first time the base changes — the stale-copy cost ADR 0043 rejects the
containment alternative for, paid only by a host that chose to hold the copy.

The check is expressed over the merge output rather than over the overlay's shape: after computing
`.[0] * .[1]` into a temporary file, each protected base path is compared against the result. One
comparison covers every route to the loss — naming the path, and replacing any ancestor of it —
without restating jq's recursion rules.

Two properties of that comparison are part of the contract, because the naive form gets them wrong.
**It is guarded.** Looking a protected path up in the merged output raises a jq type error when an
ancestor is no longer indexable — `{"hooks":"x"}` yields `Cannot index string with string
"PreToolUse"`, and `{"hooks":[]}` the array equivalent. Only a `null` ancestor indexes cleanly. An
unguarded lookup therefore aborts the install with a jq stack error naming neither the overlay nor
the path, which is the loud-and-actionable failure degrading to a loud-and-useless one. The lookup
is wrapped so a failed traversal is reported as an ordinary mismatch. **It reports outermost paths
only.** A path whose proper ancestor is already mismatching is suppressed, so `{"hooks":"x"}` names
`hooks` rather than the four array paths and every nested object path beneath it.

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

**Overlay-shape defects are on this boundary and out of this change's scope.** An overlay of two
concatenated objects passes to `jq -s '.[0] * .[1]'`, whose `.[1]` is the first document only, so
everything after it is silently dropped; a non-object overlay fails with a jq message naming the
*base* file's contents; a repeated key inside one object resolves last-wins. All three discard the
**operator's own overlay content**, not values the base defines, so none of them is the loss this
change closes, and every base protected value survives the merged-result comparison regardless.
Validating overlay shape would be a second defect class bought on the strength of a review comment
rather than a completion criterion. Issue #125 owns it. The one thing this change owes the boundary
is not making it worse, and it does not: the comparison runs on the merged result whatever shape the
overlay had.

**Control per boundary.** The overlay merge is governed by the two-clause preservation comparison
above, which is a bound (what the overlay may not do) rather than a validation of content. It fails
closed: on a mismatch nothing is deployed for that agent and the install exits non-zero. It does
not repair an already-deployed unguarded file — see ADR 0043's consequences. On failure it leaks the
overlay's filesystem path and the JSON paths of the arrays involved — both already known to the
operator reading the message, and neither containing overlay values, so a secret held in the
overlay is not echoed. JSON well-formedness is delegated to `jq`, which already fails the install
on a malformed overlay.

A directory or a dangling symlink at the overlay path fails `[[ -f "$overlay" ]]` and is treated as
"no overlay", so the bare base installs. That is left as is: the installer already prints `no
private overlay at <path>`, so the outcome is reported rather than silent, and the deployed file is
fully guarded.

**Explicitly out of scope.** An operator who edits the deployed `~/.claude/settings.json` after
install, or who edits the base file itself, is not addressed — the installer's guarantee is about
what it writes, not what happens afterward, and the manifest/prune mechanism already reports drift
on the next run. Overlay *content* is not validated: an overlay may still add a `permissions.allow`
entry that widens what Claude Code may do, which is the documented purpose of the mechanism. The
Codex TOML overlay is not covered; `merge_toml_config` concatenates sections rather than merging
JSON, so it has a different failure mode, and it is flagged rather than fixed here — issue #123
owns it, and the README wording names the JSON overlays explicitly so the new contract is not read
as covering `config.overlay.toml`. Nothing here defends against a hostile local user, who has
strictly easier paths.

## Verification

Ten assertions: four read a deployed artifact's content (1, 5, 8, 10), three assert a refusal (2, 3,
4), and three guard against over-protection (6, 7, 9).

**Isolation, stated once and applying to every item below.** `install-test.sh` exports `HOME`,
`CLAUDE_CONFIG_DIR`, `BOB_CONFIG_DIR` and `AGENT_CONFIG_PRIVATE_DIR` once, and every later run
inherits them. Items 5, 6, 8 and 9 require four mutually exclusive contents for that one private
directory, and the existing assertion at `install-test.sh:278` (`.env.AGENT_CONFIG_TEST == claude`)
depends on the original overlay staying in place. So every new assertion gets **its own
`AGENT_CONFIG_PRIVATE_DIR` and its own destination directories under `$tmpdir`**, passed per-run
rather than exported, leaving the suite's existing exported paths and assertions untouched. Item 6
adds a second fixture-repo run rather than extending the existing one, for the same reason.

The completion criterion asks for a deployed-artifact assertion that also fails if the fix is
reverted, and those two halves land on different items — item 1 reads the deployed file but passes
either way, while items 2-4 bite but read an exit status and stderr. That is not a gap, because
under this decision refusal *is* the deployed-artifact property: the installer can no longer produce
an under-guarded settings file, so "the deployed file keeps the base's hooks" and "the install
refuses" are the same guarantee observed from two sides. Item 1 pins the first, items 2-4 the
second.

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
   installs, so for this fixture nothing is deployed at all. The message content is asserted
   positively — stderr must contain both the overlay path and `hooks.PreToolUse` — so that an
   unrelated failure (a missing `jq`, a syntax error) cannot satisfy the assertion by exiting
   non-zero and deploying nothing.

3. **Object erasure.** A third install run with an overlay whose `env` is `null` must fail the same
   way. This is the clause the array check alone does not cover, and against unmodified `install.sh`
   it deploys a settings file with the base's whole `env` subtree gone.

4. **Non-indexable ancestor.** A fourth run with an overlay of `{"hooks": "x"}` must abort with a
   message naming the overlay file and `hooks`. Two assertions pin the two properties: stderr
   contains `hooks` and does *not* contain `PreToolUse`, which is simultaneously the
   outermost-only rule and proof the message is not a jq traversal error, since the jq error for
   this input is `Cannot index string with string "PreToolUse"`. Without this fixture the ancestor
   route is claimed and untested.

5. **The published example works.** A fifth run whose private overlay directory is seeded by copying
   `examples/hosts/example-host/` must succeed, and the deployed `settings.json` must carry the
   base's `hooks` and `permissions.deny` *and* the example's `permissions.allow` entry. This is the
   one part of the out-of-repo compatibility surface that is in-repo and therefore checkable, and it
   converts "the documented `permissions.allow` example keeps working" from an argument about
   today's base into a gate that fires the day a base change breaks the documented example — the
   `permissions.allow` case ADR 0009 makes plausible.

6. **The empty-array exemption.** The suite's existing fixture-repo pattern already copies `agents/`
   into `$tmpdir` and installs from the copy. Plant an empty array in the copied Claude base at a
   path the base does not otherwise define, and install with an overlay writing a non-empty array
   there; the run must succeed. This is the only protected-set rule with no in-repo instance, and
   without a constructed one an implementer who drops the word "non-empty" from the array clause
   ships a build where every other assertion still passes — surfacing later as an abort for every
   host, at exactly the moment ADR 0043 declares safe.

7. **The empty-object exemption.** An overlay of `{"mcpServers": null}` against Bob's
   `agents/bob/shared/mcp.json`, which ships `{"mcpServers": {}}`, must install successfully. This
   is the empty-container exemption's one *in-repo* instance — item 6 constructs the array half,
   which no base file has — and it is what separates the decided rule from the alternative reading
   in which every base object is protected regardless of emptiness. Without it that choice is
   documented and ungated.

8. **No overlay at all.** A run whose private overlay directory holds no `settings.overlay.json`
   must succeed, report `no private overlay at <path>`, and deploy a `settings.json` equal to
   `jq '.'` of the base. This is the default configuration for a first-time user and the path the
   README documents as supported, and it has no coverage today: the existing suite writes all four
   overlay files before its run, and the fixture-repo run inherits the same
   `AGENT_CONFIG_PRIVATE_DIR`. It is also what catches any new check misplaced above the
   `[[ -f "$overlay" ]]` guard, which would otherwise abort every such install with the whole suite
   still green.

9. **Verbatim reproduction.** An overlay whose `permissions.deny` is byte-identical to the base's
   array must install successfully and deploy that array unchanged. This is the only assertion that
   distinguishes the result-based rule from a shape-based one — against a build that aborts when the
   overlay *names* a protected path, assertions 1-8 all still pass — so without it the spec's
   load-bearing framing is documented and ungated, which is the shape ADR 0043 blames for the
   original defect.

10. **The deployed file is left unchanged by a failed run.** The abort message promises this and
    ADR 0043 repeats it, and nothing above observes it: item 2 runs in a tree where nothing was ever
    deployed. So install once with a benign overlay, then re-run the same destination with the
    clobbering `hooks.PreToolUse` overlay, and assert after the failure that the deployed
    `settings.json` still carries the base's `hooks` and `permissions.deny`. This reads deployed
    content *and* fails if the fix is reverted — the revert overwrites the good file with the
    one-hook one — so it is the item that satisfies both halves of the completion criterion at once.

Assertions 2, 3 and 4 are the ones that bite, so they are written first and observed failing
against unmodified `install.sh` before the fix lands. Assertions 6 and 9 bite in the other
direction: they fail against an implementation that over-protects.

`scripts/claude-settings-hooks-test.sh` keeps reading hooks out of the base file; its header
comment stops claiming that overlays merely "must" leave hooks alone and states that the installer
now enforces it, pointing at ADR 0043. No other region of that file is touched.

`README.md`'s Private Overlays section gains the contract in the table above, stated in the two
sentences an operator needs — and both refusals have to be in them, because an operator who reads
only "replaces an array" concludes that appending a host-specific hook is supported and meets the
abort instead. The sentences state the rule over the merged result, matching the contract above, so
the README does not publish a refusal the installer will not perform: an overlay may add new keys
and may override scalars and object members; an overlay that *changes* a path the base holds as a
non-empty array — including by extending it — or that replaces a base object with a non-object,
fails the install and names the path.

The guardrail is `just verify`, run bare.
