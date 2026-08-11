# 0047 — The git clean hook is the only guard

## Status

Accepted (2026-08-10)

## Context

`agents/claude/shared/settings.base.json` guarded `git clean` twice: two `permissions.deny`
globs — `Bash(git clean -f*)` and `Bash(git clean *-f*)` — above a `PreToolUse` hook that
reads the command and blocks it. The two disagreed about what a dangerous `git clean` is.

`3f9e7e8` added both together, both gating on a **force flag**. `47f7b92` moved the hook to
gate on a **dry run** instead, because a force flag does not mean deletion — `git clean -fn`
lists what it would remove and removes nothing, `-n` overriding `-f`. That commit changed
the hook body and the suite and never revisited the globs, which kept the force-flag
reading. Neither the hook's tests nor the suite's `assert_deny_entry` calls could see the
divergence: those calls asserted the entries were *present*, and a comment above them put
their glob semantics out of scope.

The globs are unfixable in place. A `permissions.deny` pattern is a prefix glob with no
negation, so `Bash(git clean -f*)` also matches `-fn`, `-fdn`, `-f -n` and `-f --dry-run`,
and `Bash(git clean *-f*)` also matches `-nf`, `-n -f` and `-i -f`. All seven are previews.
No narrowing exists — no prefix pattern matches `-fd` but not `-fdn`. A deny match is also
the one verdict an operator cannot approve in session, so these previews were unreachable
rather than merely awkward, which pushes whoever wanted to inspect a dirty tree toward
running the destructive form to find out what it would have done.

Against that, the globs never reached the shapes the hook exists for. A `Bash(...)` prefix
pattern cannot see `cd /tmp && git clean -fd`, `git -C /repo clean -fd`,
`git submodule foreach git clean -fd`, or `git -c clean.requireForce=false clean -d`. The
hook blocks all four.

Keeping them as defence in depth had a concrete premise until recently: a private
`settings.overlay.json` defining `hooks.PreToolUse` replaced the base array wholesale and
silently, while leaving `permissions.deny` intact — so the globs really were the surviving
layer. [ADR 0043](0043-overlays-may-not-replace-a-base-array.md) closed that route.
`install.sh` derives the base file's non-empty arrays at merge time and aborts rather than
deploying a settings file missing any of them.

## Decision

**Remove both `git clean` deny globs. The `PreToolUse` hook is the sole mechanism guarding
`git clean`.**

Two mechanisms for one job was the defect, not the safety margin: they were added together,
only one was maintained, and the stale one was the one no test could evaluate.

What the surviving mechanism promises, so a later edit can be measured against it: the hook
blocks every `git clean` **it can see in the command text** that is not a dry run — not
merely the forced ones, so `git clean -d` and `git -c clean.requireForce=false clean` are
blocked too — it permits `-n`, `-i`, `--dry-run` and `--interactive` wherever they appear in
the argument list, and it fails closed when `jq` cannot read its input.

## Consequences

- The previews come back: `git clean -fn`, `-nf`, `-fdn`, `-f -n`, `-n -f`, `-f --dry-run`
  and `-i -f`. `scripts/claude-settings-hooks-test.sh` pins all seven, so the forms this
  record restores are the forms a later regex edit has to keep restoring.
- **`git clean` becomes the only destructive command in this file guarded by a hook with no
  `permissions.deny` backstop.** `rm` keeps both layers; `git reset --hard`,
  `git push --force`, `dd`, `mkfs` and `sudo` keep deny entries and have no hook. This is
  not the removal of the last restrictive deny surface — those remain — but it is the first
  destructive command here to rely on one layer.
- Three residuals now have nothing behind them. A hook regex edited wrongly is the one the
  suite catches. **Hook-execution failure:** Claude Code treats exit 2 alone as blocking, so
  a hook that dies for an unanticipated reason exits non-2 and the command proceeds —
  shadowing `grep` with a stub that exits 2 makes this hook exit 0 on a destructive
  `git clean`, and only the `jq` branch is pinned fail-closed. Issue #139 owns it.
  **Text-matching evasion:** `C=clean; git $C -fd` is allowed, and no test can close a limit
  of text matching; issue #113 owns recording the class in the suite header.
- **A host whose `settings.json` was produced by a clobbering overlay before ADR 0043 landed
  is worse off:** it lost the hook and kept the deny array, so the globs were still refusing
  its plain `git clean -fd`, and now nothing is. Issue #126 owns repairing an
  already-deployed settings file. This record does not lengthen that window; it empties it.
- Reversible at the price the record names: re-adding two array entries restores the old
  state, unappealable previews included.

## Considered & rejected

- **Keep both entries as defence in depth** (issue #111, option 2). Rejected on price, with
  both premises corrected first. The keep-argument's premise — hooks vanish through an
  overlay — expired with ADR 0043; but the counter-argument that a deny entry and a hook
  fail together is also false, since a deny match is in-process while a hook is a
  subprocess, so the entries really would still refuse an uncompounded `git clean -fd` in
  the fail-open case above. Price settles it: they cost every force-flagged preview,
  permanently and unappealably, and buy coverage only of the uncompounded form — not of
  `cd /tmp && ...`, `git -C`, or `submodule foreach`.
- **Keep only `Bash(git clean -f*)`**, the narrower of the two. `Bash(git clean *-f*)`
  matches a strict superset, so keeping the broad one instead is worse on every count this
  record weighs, and the narrow one is the only compromise worth pricing. Rejected because
  it is where most of the cost lives: it still refuses `-fn`, `-fdn`, `-f -n` and
  `-f --dry-run` — four of the seven forms this record exists to restore — while still
  buying nothing for the compounded shapes.
- **Remove only after #139 and #126 land**, so the fail-open window and the clobbered host
  are never unbacked. Rejected on the exchange rate: waiting keeps an unappealable false
  positive on every host for the whole interval, to cover a hook dying for a reason its body
  did not anticipate — neither observed here nor reported. The dependency that did have an
  observed route, the overlay, is the one that was made a precondition, and it has landed.
- **Move both entries from `deny` to `ask`.** The `permissions` object is not deny-only, and
  an `ask` entry prompts rather than refusing — the one settings-layer option that keeps a
  backstop without making previews unreachable. Rejected: it contradicts the
  single-mechanism decision recorded here, and while the hook is healthy it fires *only* on
  previews, since every destructive form is blocked before the operator sees a prompt. It
  buys the fail-open backstop at the price of a prompt on every dry run, where #139 buys it
  for nothing. [ADR 0009](0009-native-permission-lists-grant-capabilities.md) frames
  `permissions.deny` as the checked-in restrictive surface and rejects adding permission
  fields for symmetry; this is consistent with that.
- **Enumerate the destructive bundles** rather than matching a prefix. Rejected: bundle
  order is free and abbreviations are accepted (`--f` and `--fo` are `--force`), so the list
  is unbounded and the first form nobody thought of is allowed. Deciding by parsing is what
  the hook already does.
- **Do nothing and document the false positives.** Rejected: the documentation would say
  that the recommended way to inspect a tree before deleting from it is denied, and the
  operator cannot approve past a deny.
