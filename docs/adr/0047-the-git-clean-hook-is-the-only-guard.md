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

The force-anchored globs cannot be narrowed to fix that. A `permissions.deny` pattern is a
prefix glob with no negation, so `Bash(git clean -f*)` also matches `-fn`, `-fdn`, `-f -n`
and `-f --dry-run`, and `Bash(git clean *-f*)` also matches `-nf`, `-n -f` and `-i -f` —
seven previews, none of which deletes anything. No pattern anchored on the force flag
separates them: none matches `-fd` but not `-fdn`. A deny match is also the one verdict an
operator cannot approve in session, so those seven spellings were unreachable rather than
merely awkward.

Be exact about what that cost, because the rest of this record depends on it. A force flag
contributes nothing to an invocation that deletes nothing, so each denied spelling has an
always-reachable equivalent: `-fn` is `-n`, `-fdn` is `-dn`, `-f --dry-run` is `--dry-run`,
`-i -f` is `-i`. Neither glob matched `-n`, `-nd`, `-ndx`, `-dn`, `--dry-run`, `-i` or
`--interactive`, and the hook allows all of them, so previewing a dirty tree was available
at both layers throughout. What the entries denied was a set of redundant spellings, not the
capability to preview.

The hook reaches shapes the globs never could — `cd /tmp && git clean -fd`,
`git -C /repo clean -fd`, `git submodule foreach git clean -fd`,
`git -c clean.requireForce=false clean -d`. A prefix glob also matches whatever follows it,
so it covered a shape the hook misparses; the Consequences price that.

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
only one was maintained, and the stale one was the one no test could evaluate. What the
guard does is not restated here — `scripts/claude-settings-hooks-test.sh` is the maintained
executable description, and a second prose copy in an immutable record is the drift this
decision ends.

## Consequences

- The seven force-plus-preview spellings become usable: `git clean -fn`, `-nf`, `-fdn`,
  `-f -n`, `-n -f`, `-f --dry-run` and `-i -f`. The suite pins all seven. Per the Context,
  this is an ergonomic gain rather than a restored capability — the force-free equivalents
  were never denied — so it should be weighed as one.
- **The change also loses coverage, and the loss is on destructive commands.** git stops
  parsing options at `--`, so a preview flag after the separator is a pathspec — but the
  hook reads it as a dry run. `git clean -fd -- build/ -n` deletes (confirmed on git 2.55.0,
  which printed `Removing build/`) and the hook allows it. The removed prefix glob matched
  it. **That is the honest exchange rate: a spelling convenience bought with a real guard on
  a destructive form, unbacked until issue #141 lands.** The `--` gap is not closed here
  because the hook body is outside this change's surface; #141 owns it.
- **`git clean` becomes the only destructive command in this file relying on a hook with no
  `permissions.deny` backstop.** `rm` keeps both layers. `git reset --hard`, `dd`, `mkfs`
  and `sudo` keep deny entries and have no hook. `git push --force` is the mixed case: a
  deny entry plus a hook that covers `main`/`master` only, so force-pushing another branch
  rests on the deny entry alone.
- Two further residuals now have nothing behind them. **Hook-execution failure:** Claude
  Code treats exit 2 alone as blocking, so a hook that dies for an unanticipated reason
  exits non-2 and the command proceeds — shadowing `grep` with a stub that exits 2 makes
  this hook exit 0 on a destructive `git clean`, and only the `jq` branch is pinned
  fail-closed. Issue #139 owns it. **Text-matching evasion:** `C=clean; git $C -fd` is
  allowed, and no test can close a limit of text matching; issue #113 owns recording the
  class in the suite header.
- An already-deployed `settings.json` is unaffected until its host re-installs, and after
  that ADR 0043 leaves a clobbering overlay aborting with the deployed file untouched, or a
  fixed overlay carrying the base `hooks.PreToolUse` array verbatim. The abort preserves
  whatever is already there, so a host whose pre-0043 overlay clobbered **both** arrays
  keeps a file with neither mechanism; issue #126 owns repairing those. This change neither
  creates nor worsens that state.
- The suite gains no assertion for the `--` forms. Pinning a destructive command as
  *allowed* would read as sanctioning it and would have to be deleted the moment #141 lands;
  the issue is the honest owner.
- Reversible at the price the record names: re-adding two array entries restores the old
  state, unreachable spellings included.

## Considered & rejected

- **Keep both entries as defence in depth** (issue #111, option 2). Rejected on price, with
  both premises corrected first. The keep-argument's premise — hooks vanish through an
  overlay — expired with ADR 0043; but the counter-argument that a deny entry and a hook
  fail together is also false, since a deny match is in-process while a hook is a
  subprocess. The entries would still refuse an uncompounded `git clean -fd` in the
  fail-open case, and would still refuse the `--` forms. Price settles it: they cost all
  seven spellings, permanently and unappealably, and #141 buys the coverage back without
  that cost. That price is smaller than it first looked, which is why this was the closest
  call in the list and why the record states the exchange rate above rather than burying it.
- **Keep only `Bash(git clean -f*)`**, the narrower of the two — the broader one matches a
  strict superset, so it is worse on every count here. Rejected on the same price ground: it
  still refuses four of the seven spellings while buying back only part of the coverage.
- **Move both entries from `deny` to `ask`.** An `ask` entry prompts rather than refusing,
  and the operator can approve, so it keeps the spellings reachable — and being a prefix
  glob it would still cover the `--` forms the hook misses. Rejected on the two costs that
  survive: a prompt on every force-flagged preview for as long as it stays, and a second
  settings-layer mechanism for one job, which is the arrangement this record removes.
- **Anchor a deny entry on the separator instead** — `Bash(git clean * -- *)`, aimed at the
  lost coverage rather than at the force flag. Rejected on the same second-mechanism ground,
  and on price: it would refuse `git clean -n -- build/`, a genuine preview the suite pins
  as allowed, and it would have to be deleted again once #141 lands. Left to #141 by choice
  rather than ruled out as inexpressible.
- **Remove only after #139 and #141 land**, so no window is left unbacked. Rejected on the
  exchange rate the operator set, and on sequencing: #141 is a hook fix, so it can land
  without the globs and is not blocked by this change.
- **Do nothing.** Rejected: the two entries would stay stale against the hook, which is the
  defect issue #111 reports, and a record documenting the false positives would have to be
  maintained alongside them. Its cost is smaller than a reader might assume — the
  force-free previews were always available — so this option was rejected on the
  two-mechanism drift rather than on operator friction.
