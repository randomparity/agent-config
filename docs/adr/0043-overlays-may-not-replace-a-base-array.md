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
replace an array the base defines. An overlay that would is a hard install failure naming
the offending paths.**

The protected set is **derived from the base file at merge time**, not enumerated in
`install.sh`: every path in the base whose value is an array is protected, for all three
call sites, with no per-agent configuration. That derivation is the point. A hardcoded
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

Failure is loud and total: the install aborts, names the overlay file and each path it
would have replaced, and deploys nothing. A guardrail file that half-installed would be
worse than one that did not install, because the operator would have no signal that the
tree they are working in is unguarded.

Adding to a protected array is not supported. The rejected alternatives below explain why
the capability is not worth its cost here; when a host genuinely needs a host-specific
hook, this record is the thing to revisit, with a real requirement in hand rather than an
anticipated one.

## Consequences

- The documented `permissions.allow` overlay in `examples/hosts/example-host/` keeps
  working unchanged. The base defines no `permissions.allow`, so the overlay *adds* an
  array rather than replacing one, and adding is unaffected.
- A host that wants an extra hook can no longer get one through an overlay, and now
  learns that at install time instead of discovering it after an unguarded `git clean`.
  The capability was never actually available — an overlay that tried bought one hook at
  the price of five — so what changes is the honesty of the failure, not the capability.
- Overriding an existing array member's value is impossible even when the override is
  benign: an overlay cannot change one entry of `permissions.deny` without replacing the
  array. Accepted. The base's deny list is public, shared, and deliberately not a
  per-host decision.
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
- **Do nothing and rely on the header comment.** Rejected by the issue: the comment is
  read by people, once, and the file it protects is edited by agents that never open it.
- **Support merging into protected arrays via an explicit overlay directive** — an
  `"append"` marker or a separate `settings.append.json`. Rejected as speculative: no host
  in this repository needs a host-specific hook, and the directive would add a second
  overlay grammar to keep correct in exchange for a requirement nobody has stated.
