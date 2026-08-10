# 0043 — Overlays may not replace a base array

## Status

Accepted (2026-08-10)

## Context

`install.sh` merges a private, out-of-repo `settings.overlay.json` into a public base
settings file with `jq -s '.[0] * .[1]'`. jq's `*` recurses into objects and **replaces**
arrays. Every array the base defines is therefore erasable by an overlay that names its
path, and the erasure is silent: the deployed `settings.json` is valid JSON, Claude Code
starts normally, and nothing reports the loss.

What is erasable is not incidental. `agents/claude/shared/settings.base.json` holds five
arrays — `permissions.deny`, `hooks.PreToolUse`, `hooks.Stop`, and the inner `hooks` array
of each. Between them they carry the repository's destructive-operation guards and its 33
deny entries. An overlay adding one host-specific hook has to write `hooks.PreToolUse`,
and writing it drops all five guards in that array. The host that wanted *one more* guard
gets *none*.

The constraint is already documented — `scripts/claude-settings-hooks-test.sh` says
"Overlays must leave `hooks` alone" in its header — and that comment is the entire defence.
No gate reads it. `install-test.sh` asserts that overlay-merged `env` and `mcp` values
arrive, but never that base values survive, so the suite is green in exactly the
configuration the comment warns about.

The same function serves three call sites: the Claude settings overlay, the Bob settings
overlay, and the Bob MCP overlay. Bob's two base files hold no arrays today, so only the
Claude site is currently exploitable and Bob's sites are protected vacuously — but
"currently" is the whole problem, since the guards this protects were themselves added to
the base file after the overlay mechanism shipped.

## Decision

**An overlay may add, and it may override a value it names, but it may not erase a value
it does not name.**

Two clauses enforce that, both **derived from the base file at merge time** rather than
enumerated in `install.sh`:

- a **non-empty array** in the base must be *identical* in the merged output; and
- an **object** in the base must still be *an object* in the merged output.

The first clause is the reported defect. The second closes the same loss by the other
route: `*` merges two objects harmlessly, but an overlay writing `"env": null` or
`"env": "off"` replaces the whole subtree and drops every base member of it, with the
arrays elsewhere still intact and the check on them still passing. Requiring the base's
objects to stay objects is sufficient, because once `*` recurses, every base member
survives unless the overlay names it.

Scalars are unprotected: overriding one loses only the value the overlay named, which is
what an overlay is for. An **empty** base array is unprotected for the same reason —
replacing `[]` erases nothing — and that exemption is load-bearing, because it keeps
seeding a base key with an empty default from breaking every host already writing that key.

Deriving the protected set from the base is the point. A hardcoded list of `hooks` and
`permissions.deny` would need an edit whenever a base file grew a new container, which is
the drift that produced this defect: the guards the header comment protects were added to
the base without the merge learning about them. Derivation means a new guarded value is
protected the moment it is written, in every base file, with no per-agent configuration.

The check is stated over the merge's *output*, not over the overlay's shape: after
computing `.[0] * .[1]`, each protected base path is compared against the result. That
formulation catches every route to the loss with one comparison — naming the path directly,
and replacing any ancestor of it — without `install.sh` restating jq's recursion rules.

Failure is loud: the install aborts, naming the overlay file and each path it would have
erased, and saying that the currently deployed settings file is unchanged and may already
be missing those values. Every `merge_json_settings` call for an agent runs before that
agent's first deploy, so the offending agent deploys nothing and no partially merged
settings file is ever written. Under `--agent all` the agents installed earlier in the
sequence remain deployed, each from its own base or its own valid overlay. The guarantee is
per-agent, not per-run, and that is the honest statement of it: what must not happen is a
settings file that is deployed and unguarded.

Adding to a protected array is not supported; the rejected alternatives below weigh both
routes to it.

## Consequences

- The documented `permissions.allow` overlay in `examples/hosts/example-host/` keeps
  working unchanged. The base defines no `permissions.allow`, so the overlay *adds* an
  array rather than replacing one, and adding is unaffected.
- A host that wants an extra hook can no longer get one through an overlay, and now
  learns that at install time instead of discovering it after an unguarded `git clean`.
  The capability was never actually available — an overlay that tried bought one hook at
  the price of five — so what changes is the honesty of the failure, not the capability.
- Overriding one member of a protected array is impossible even when the override is
  benign. The sharpest case is a **host-private `permissions.deny` entry**: this
  repository is public, so a deny naming an employer-specific path is exactly what the
  private-overlay mechanism exists to hold, and under this decision its only route is a
  change to the public base — publishing the path the operator was trying not to publish.
  [ADR 0009](0009-native-permission-lists-grant-capabilities.md) records that overlays may
  add `permissions.allow`; this record makes the restrictive half of that surface
  non-extendable, and a host needing a private deny entry must publish it or do without.
- **A base file's non-empty arrays and its objects are now an out-of-repo compatibility
  surface.** Adding one at a path some host's private overlay already writes aborts that
  host's next install — and overlays are private, so no CI run, no test here, and no
  reviewer of the base-file change can see it coming. Such a base-file change is a contract
  change and gets called out as one. Seeding a key with `[]` is deliberately not, per the
  empty-array exemption above.
- **The guarantee covers what the installer writes, not what is already deployed.** A host
  whose current `settings.json` was produced by a clobbering overlay stays unguarded until
  the overlay is fixed and the install re-run — and the abort *lengthens* that window,
  because the run that used to complete now does nothing. The abort message says so, which
  is the only thing that turns this residual into an operator instruction.
- The published overlay contract narrows, so `README.md` states it rather than leaving it
  to be inferred from jq's behavior.
- The merge reads its input twice — once to merge, once to compare — and the failure path
  depends on `jq`, which `merge_json_settings` already requires.
- `merge_toml_config` is untouched and has no equivalent guarantee. Codex's TOML overlay
  concatenates rather than merges, so its failure mode is different and is not addressed
  here.

## Considered & rejected

- **Deep-merge with array union.** Rejected: `hooks.PreToolUse` is order-bearing and
  duplicate-sensitive, so unioning the base's real hooks arrays with an overlay's produces
  a hook list nobody authored. A rule that is defensible for a set like `permissions.deny`
  and corrupting for an ordered list trades a loud loss for a quiet one.
- **Apply the overlay, then reassert the base's protected values.** Rejected: it keeps the
  guards but makes the overlay's stated intent vanish without a word, replacing one silent
  failure with another. An operator who writes `hooks.PreToolUse` and sees a clean install
  has been told their hook is active; it is not. It does have one advantage the abort
  lacks — it would *repair* an already-unguarded deployment on the next run rather than
  leaving it in place — and that is not enough to buy a second silent failure mode.
- **A hardcoded protected-key list (`hooks`, `permissions.deny`).** Rejected: it protects
  the values someone remembered, not the values that exist.
- **Require containment rather than equality** — the merged array must *contain* every
  base element, so a host may write `hooks.PreToolUse` with the base's entries plus its
  own. Rejected, and it is the closest call here: it costs one operator in the same
  comparison and would close the loss without closing the use cases — host-specific hooks
  *and* host-private deny entries, both foreclosed above. What sinks it is that it makes
  every host that customizes an array hold a copy of the base's contents in a private file.
  That copy goes stale the moment the base gains a guard — which is the event the whole
  record exists for — and the host learns at its next install, having run unguarded in
  between.
- **Warn and continue.** Rejected: install output is long, the warning would land in the
  middle of it, and the failure it describes is the silent removal of destructive-operation
  guards. A warning that can be missed is the status quo with extra text.
- **Do nothing and rely on the header comment.** Rejected: the comment is read by people,
  once, and the file it protects is edited by agents that never open it. The loss has not
  been observed here and only the Claude site is exploitable today, which is a fair
  argument for a weaker remedy and not for none — the values at stake are
  destructive-operation guards, and their loss leaves no trace to find later, so the first
  observation would be the damage.
- **Support merging into protected arrays via an explicit overlay directive** — an
  `"append"` marker or a separate `settings.append.json`. Rejected as speculative: it adds
  a second overlay grammar to keep correct in exchange for a requirement nobody has stated.
