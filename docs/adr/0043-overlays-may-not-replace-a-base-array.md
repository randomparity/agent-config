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
Claude site is currently exploitable — but "currently" is the whole problem, since the
guards this protects were themselves added to the base file after the overlay mechanism
shipped.

## Decision

**An overlay may add and it may override a scalar or an object member, but it may not
replace a non-empty array the base defines. An overlay that would is a hard install failure
naming the offending paths.**

The predicate is arrays and not every base value because of what each loss costs. An
overlay that overrides a scalar loses only the value it named — `statusLine.command` is
replaced by the one the author wrote, which is what they asked for. An overlay that
replaces an array loses siblings it never named and may not know exist. An **empty** base
array has no such siblings, so it is not protected: replacing `[]` loses nothing, and
protecting it would turn seeding a base key with an empty default into an install failure
for every host already writing that key.

The protected set is **derived from the base file at merge time**, not enumerated in
`install.sh`: every path in the base whose value is a non-empty array is protected, for all
three call sites, with no per-agent configuration. That derivation is the point. A hardcoded
list of `hooks` and `permissions.deny` would have to be edited whenever a base file grows
a new array — which is the drift that produced this defect, since the guards the comment
protects were added to the base without the merge learning about them. Deriving from the
base means a new guarded array is protected the moment it is written, in every base file,
including Bob's two empty ones.

The check is stated over the merge's *output*, not over the overlay's shape: after
computing `.[0] * .[1]`, every array path in the base must still hold an identical array
in the result. That formulation catches every route to the loss with one comparison —
naming the array path directly, and replacing any ancestor of it with a non-object —
without `install.sh` having to reason about jq's recursion rules a second time.

Failure is loud: the install aborts, naming the overlay file and each path it would have
replaced. Every `merge_json_settings` call for an agent runs before that agent's first
deploy, so the offending agent deploys nothing and no partially merged settings file is
ever written. Under `--agent all` the agents installed earlier in the sequence — Claude,
then Codex, then Bob — remain deployed, each from its own base or its own valid overlay.
The guarantee is per-agent, not per-run, and that is the honest statement of it: what must
not happen is a settings file that is deployed and unguarded.

Adding to a protected array is not supported. The rejected alternatives below weigh both
routes to it — a new overlay grammar, and requiring containment instead of equality — and
neither is worth its cost here; when a host genuinely needs a host-specific hook, this
record is the thing to revisit, with a real requirement in hand rather than an anticipated
one.

## Consequences

- The documented `permissions.allow` overlay in `examples/hosts/example-host/` keeps
  working unchanged. The base defines no `permissions.allow`, so the overlay *adds* an
  array rather than replacing one, and adding is unaffected.
- A host that wants an extra hook can no longer get one through an overlay, and now
  learns that at install time instead of discovering it after an unguarded `git clean`.
  The capability was never actually available — an overlay that tried bought one hook at
  the price of five — so what changes is the honesty of the failure, not the capability.
- Overriding one member of a protected array is impossible even when the override is
  benign, for every such array and not just the ones whose contents are guards. Accepted:
  the base's arrays are public and shared, and a host that needs one of them to differ is
  asking for a base-file change, not an overlay.
- **A base file's non-empty arrays are now an out-of-repo compatibility surface.** Adding
  an array to a base file at a path some host's private overlay already writes aborts that
  host's next install — and overlays are private, so no CI run, no test here, and no
  reviewer of the base-file change can see it coming. A base-file change that introduces a
  non-empty array is therefore a contract change and gets called out as one. Seeding a key
  with `[]` is deliberately not: an empty base array is unprotected, which is what keeps a
  future `permissions.allow: []` in the base from breaking the documented example-host
  overlay that [ADR 0009](0009-native-permission-lists-grant-capabilities.md) expects hosts
  to write.
- The published overlay contract narrows, so `README.md` states it rather than leaving it
  to be inferred from jq's behavior.
- The merge now reads its input twice — once to merge, once to compare — and the failure
  path depends on `jq` being present, which `merge_json_settings` already requires.
- Bob's two base files gain the protection for free and assert nothing today, because
  neither contains an array. The check costs one jq invocation per merge to say so.
- `merge_toml_config` is untouched and has no equivalent guarantee. Codex's TOML overlay
  concatenates rather than merges, so its failure mode is different and is not addressed
  here.

## Considered & rejected

- **Deep-merge with array union.** Rejected: it is wrong for arrays that are argument
  vectors rather than sets. Bob's MCP overlay shape has `"args": ["-y", "<server>"]`, and
  a union of two such arrays is not a command line anyone wrote. A rule that is right for
  `permissions.deny` and silently corrupting for `args` trades a loud loss for a quiet
  one.
- **Apply the overlay, then reassert the base's protected keys.** Rejected: it keeps the
  guards but makes the overlay's stated intent vanish without a word, replacing one silent
  failure with another. An operator who writes `hooks.PreToolUse` and sees a clean install
  has been told their hook is active; it is not.
- **A hardcoded protected-key list (`hooks`, `permissions.deny`).** Rejected: it protects
  the arrays someone remembered, not the arrays that exist, and it needs an edit in
  `install.sh` every time a base file grows one. The defect being fixed is precisely a
  guarantee that did not keep up with the base file.
- **Warn and continue.** Rejected: install output is long, the warning would land in the
  middle of it, and the failure it describes is the silent removal of destructive-operation
  guards. A warning that can be missed is the status quo with extra text.
- **Require containment rather than equality** — the merged array must *contain* every
  base element, so a host may write `hooks.PreToolUse` with the base's entries plus its
  own. Rejected, and it is the closest call here: it costs one operator in the same
  comparison and would close the loss without closing the use case. What sinks it is that
  it makes every host that customizes an array hold a copy of the base's contents in a
  private file. That copy goes stale the moment the base gains a guard — which is the
  event the whole record exists for — and the host learns at its next install, having run
  unguarded in between. It also buys that cost for a use case no host in this repository
  has: nobody needs a host-specific hook today.
- **Do nothing and rely on the header comment.** Rejected: the comment is read by people,
  once, and the file it protects is edited by agents that never open it. The loss has not
  been observed here and only the Claude site is exploitable today, which is a fair
  argument for a weaker remedy and not for none — the arrays at stake are
  destructive-operation guards, and their loss leaves no trace to find later, so the first
  observation would be the damage.
- **Support merging into protected arrays via an explicit overlay directive** — an
  `"append"` marker or a separate `settings.append.json`. Rejected as speculative: no host
  in this repository needs a host-specific hook, and the directive would add a second
  overlay grammar to keep correct in exchange for a requirement nobody has stated.
