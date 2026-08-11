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
and `Bash(git clean *-f*)` also matches `-nf`, `-n -f` and `-i -f` — seven previews, none of
which deletes anything. No narrowing exists: no prefix pattern matches `-fd` but not `-fdn`.
A deny match is also the one verdict an operator cannot approve in session, so these
previews were unreachable rather than merely awkward, which pushes whoever wanted to inspect
a dirty tree toward running the destructive form to find out what it would have done.

The hook reaches shapes the globs never could — `cd /tmp && git clean -fd`,
`git -C /repo clean -fd`, `git submodule foreach git clean -fd`,
`git -c clean.requireForce=false clean -d`. The reverse is also true, and matters more: a
prefix glob matches whatever follows it, so it covered forms the hook misparses. That
asymmetry is priced in the Consequences rather than waved away.

Keeping the globs as defence in depth had a second premise until recently: a private
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

What the surviving mechanism actually does, stated so a later edit can be measured against
it rather than flattered by it: the hook blocks a `git clean` it can see in the command text
unless that text contains `-n`, `-i`, `--dry-run` or `--interactive`. It blocks more than
the forced ones — `git clean -d` and `git -c clean.requireForce=false clean` included — and
it fails closed when `jq` cannot read its input. It does **not** parse `--`, so a preview
flag after the separator is a pathspec to git and a dry-run signal to the hook; issue #141
owns that.

## Consequences

- The previews come back: `git clean -fn`, `-nf`, `-fdn`, `-f -n`, `-n -f`, `-f --dry-run`
  and `-i -f`. `scripts/claude-settings-hooks-test.sh` pins all seven, so the forms this
  record restores are the forms a later regex edit has to keep restoring.
- **This is a coverage loss as well as a restoration, and the loss is on destructive
  commands.** `git clean -fd -- build/ -n` deletes — confirmed on git 2.55.0, which printed
  `Removing build/` — and the hook allows it, because it sees `-n`. The removed prefix glob
  matched it. So the trade is not previews-for-nothing: it is seven unreachable previews
  bought back at the cost of the `--` forms, which now have no guard until issue #141 lands.
  A reader deciding whether to re-add the globs should weigh that, not the framing that this
  removed only false positives.
- **`git clean` becomes the only destructive command in this file guarded by a hook with no
  `permissions.deny` backstop.** `rm` keeps both layers; `git reset --hard`,
  `git push --force`, `dd`, `mkfs` and `sudo` keep deny entries and have no hook. This is
  not the removal of the last restrictive deny surface — those remain — but it is the first
  destructive command here to rely on one layer.
- Two further residuals now have nothing behind them. **Hook-execution failure:** Claude
  Code treats exit 2 alone as blocking, so a hook that dies for an unanticipated reason
  exits non-2 and the command proceeds — shadowing `grep` with a stub that exits 2 makes
  this hook exit 0 on a destructive `git clean`, and only the `jq` branch is pinned
  fail-closed. Issue #139 owns it. **Text-matching evasion:** `C=clean; git $C -fd` is
  allowed, and no test can close a limit of text matching; issue #113 owns recording the
  class in the suite header.
- An already-deployed `settings.json` is unaffected by this change until its host
  re-installs, and ADR 0043 makes the unguarded-on-install state unreachable after that: a
  clobbering overlay aborts the install, leaving the deployed file as it was, and a fixed
  one carries the base `hooks.PreToolUse` array verbatim. So no host ends up with neither
  mechanism.
- The suite gains no assertion for the `--` forms. Pinning a destructive command as
  *allowed* would read as sanctioning it and would have to be deleted the moment #141 lands;
  the issue is the honest owner.
- Reversible at the price the record names: re-adding two array entries restores the old
  state, unappealable previews included.

## Considered & rejected

- **Keep both entries as defence in depth** (issue #111, option 2). Rejected on price, with
  both premises corrected first. The keep-argument's premise — hooks vanish through an
  overlay — expired with ADR 0043; but the counter-argument that a deny entry and a hook
  fail together is also false, since a deny match is in-process while a hook is a
  subprocess. The entries would still refuse an uncompounded `git clean -fd` in the
  fail-open case, and would still refuse the `--` forms. Price settles it: they cost all
  seven previews, permanently and unappealably, and #141 buys the coverage back without
  that cost.
- **Keep only `Bash(git clean -f*)`**, the narrower of the two — the broader one matches a
  strict superset, so it is worse on every count here. Rejected because the narrow entry is
  where most of the cost lives: it still refuses four of the seven forms this record exists
  to restore.
- **Remove only after #139 and #141 land**, so no window is left unbacked. This is the
  closest call in the list, and it got closer once the `--` gap was found: unlike the
  fail-open case, that gap is reachable by an ordinary command with no evasion. Rejected on
  the exchange rate the operator set — the previews are unappealable on every host and every
  day the entries stay, while the gap needs a `--` an agent has little reason to write — and
  on sequencing: #141 is a hook fix, so it can land without the globs and is not blocked by
  this change. Removing first does not make it harder.
- **Move both entries from `deny` to `ask`.** The `permissions` object is not deny-only, and
  an `ask` entry prompts rather than refusing — the one settings-layer option that keeps a
  backstop without making previews unreachable. Rejected: it contradicts the
  single-mechanism decision recorded here, and it fires on every preview while the hook is
  healthy, since destructive forms are blocked before the operator sees a prompt.
  [ADR 0009](0009-native-permission-lists-grant-capabilities.md) frames `permissions.deny`
  as the checked-in restrictive surface and rejects adding permission fields for symmetry;
  this is consistent with that.
- **Enumerate the destructive bundles** rather than matching a prefix. Rejected: bundle
  order is free and abbreviations are accepted (`--f` and `--fo` are `--force`), so the list
  is unbounded and the first form nobody thought of is allowed.
- **Do nothing and document the false positives.** Rejected: the documentation would say
  that the recommended way to inspect a tree before deleting from it is denied, and the
  operator cannot approve past a deny.
