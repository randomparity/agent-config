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
Claude site is exploitable by the reported route — but "currently" is the whole problem,
since the guards this protects were themselves added to the base file after the overlay
mechanism shipped.

## Decision

**A non-empty array the base defines must survive the merge unchanged, and an object the
base defines must still be an object after it. An overlay that breaks either is a hard
install failure.**

The rule is normative over the *merged result*, not over what the overlay may write,
because the result is what the installer can check and what an assertion against a deployed
file can verify. Both clauses are **derived from the base file at merge time** rather than
enumerated in `install.sh`: after computing `.[0] * .[1]`, a non-empty base array must be
identical in the result, and a base object must still be an object there.

In practice that means an overlay must not write a path the base holds as a non-empty array
— extending it included, since a longer array is not an identical one. An overlay that
reproduces the base's array *verbatim* does pass, and will abort the first time the base
changes: that is the stale-copy failure the containment alternative is rejected for below,
reached only by a host that chose to hold the copy.

The first clause is the reported defect. The second is narrower than it looks, and worth
being precise about: any base object with a non-empty array beneath it is *already* covered
by the first clause, since `"hooks": null` makes `hooks.PreToolUse` absent from the result
and the array check fails. What the second clause uniquely protects, in today's base, is the
objects holding only scalars — `env` and `statusLine` — and what it protects them from is
whole-subtree erasure, nothing more. `"env": null` aborts; `{"env": {"DISABLE_TELEMETRY":
"0"}}` merges and deploys, because scalars are unprotected. So an overlay can still turn the
telemetry defaults back on by naming them, and what it cannot do is drop all four at once
without naming any. That is the honest scope of the clause: `env` is not a guarded value,
and losing its members together is worth refusing even though losing one by name is not.

Scalars are unprotected: overriding one loses only the value the overlay named, which is
what an overlay is for. An **empty** base container is unprotected for the same reason, and
symmetrically for both kinds — replacing `[]` or `{}` erases nothing — so both clauses read
"non-empty". Objects are where that exemption bites today: `agents/bob/shared/settings.base.json`
is `{}` and `agents/bob/shared/mcp.json` holds `mcpServers` as `{}`, so an overlay writing
`{"mcpServers": null}` installs rather than aborting. For arrays it has no in-repo instance
at all — no base file holds an empty array — which makes it the one part of the protected-set
rule a test has to construct, and the one that keeps a future seeded `[]` from aborting every
host already writing that key.

Failure is loud: the install aborts, naming the overlay file and each path it would have
erased, and saying that the currently deployed settings file is unchanged and may already
be missing those values. Every `merge_json_settings` call for an agent runs before that
agent's first deploy, so the offending agent deploys nothing and no partially merged
settings file is ever written. Under `--agent all` the agents installed earlier in the
sequence remain deployed, each from its own base or its own valid overlay. The guarantee is
per-agent, not per-run, and that is the honest statement of it: what must not happen is a
settings file that is deployed and unguarded.

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
  Issue #118 owns closing that gap.
- **A base file's non-empty arrays and its objects are now an out-of-repo compatibility
  surface.** Adding one at a path some host's private overlay already writes aborts that
  host's next install — and overlays are private, so no CI run, no test here, and no
  reviewer of the base-file change can see it coming. Such a base-file change is a contract
  change and gets called out as one. Seeding a key with `[]` is deliberately not — but it is
  the first half of a two-step break, because hosts start writing the path while it is empty
  and every one of them aborts when the base puts its first real entry there. That later
  edit is the contract change, and it is the one to call out.
- **The guarantee covers what the installer writes, not what is already deployed.** A host
  whose current `settings.json` was produced by a clobbering overlay stays unguarded until
  the overlay is fixed and the install re-run — and the abort *lengthens* that window,
  because the run that used to complete now does nothing. The abort message says so, which
  is the only thing that turns this residual into an operator instruction. Issue #126 owns
  closing it.
- The published overlay contract narrows, so `README.md` states it rather than leaving it
  to be inferred from jq's behavior.
- The merge reads its input twice — once to merge, once to compare — and the failure path
  depends on `jq`, which `merge_json_settings` already requires.
- `merge_toml_config` is untouched and has no equivalent guarantee. Codex's TOML overlay
  concatenates rather than merges, so its failure mode is different and is not addressed
  here.

## Considered & rejected

- **Deep-merge with array *union*** — combine both sides as sets. Rejected on set semantics
  specifically: `hooks.PreToolUse` is order-bearing and duplicate-sensitive, so reordering
  and de-duplicating it produces a hook list nobody authored.
- **Base-first *concatenation*** — where the base holds a non-empty array and the overlay
  writes that path, emit the base's elements in order followed by the overlay's. This is a
  genuinely different option from union and the strongest one here: the guards are preserved
  structurally rather than by a check a refactor could skip, no host holds a copy of the base
  so nothing goes stale, no second overlay grammar is added, and it would close the
  host-private deny gap now deferred to #118. Rejected on two grounds that apply to it and
  not to union. First, it answers an overlay that writes a guarded path — an author who
  believes they are replacing — by silently appending instead, so the operator's mistaken
  intent produces a settings file they did not write and no message says so; this record's
  complaint against the status quo is silence, and quiet reinterpretation is a poorer trade
  than the loud stop. Second, strictness is the reversible direction: abort can be loosened
  to concatenation on a real request without breaking any host, while concatenation cannot
  later be tightened without breaking every host that came to rely on appending. It also
  does not address the object route, so the second clause would be needed regardless.
- **Apply the overlay, then reassert the base's protected values.** Rejected: it keeps the
  guards but makes the overlay's stated intent vanish without a word, replacing one silent
  failure with another. An operator who writes `hooks.PreToolUse` and sees a clean install
  has been told their hook is active; it is not. It does have one advantage the abort
  lacks — it would *repair* an already-unguarded deployment on the next run rather than
  leaving it in place — and that is not enough to buy a second silent failure mode.
- **A hardcoded protected-key list (`hooks`, `permissions.deny`).** Rejected: it protects
  the values someone remembered, not the values that exist, and needs an edit whenever a
  base file grows a container. That is the drift that produced this defect — the guards the
  header comment protects were added to the base without the merge learning about them.
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
  `"append"` marker or a separate `settings.append.json`. Not rejected as unwanted: the
  requirement is real and this record states it above, where a host-private
  `permissions.deny` entry has no route that does not publish the path. Deferred rather than
  solved here, because the price is a second overlay grammar to keep correct and this change
  is a defect fix; issue #118 owns it. Until then the operator publishes the entry in the
  base or does without, and that is accepted, not overlooked.
