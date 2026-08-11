# 0047 — The git clean hook is the only guard

## Status

Accepted (2026-08-10)

## Context

`agents/claude/shared/settings.base.json` guarded `git clean` twice. Two `permissions.deny`
globs — `Bash(git clean -f*)` and `Bash(git clean *-f*)` — sat above a `PreToolUse` hook
that reads the command and blocks it. The two disagreed about what a dangerous `git clean`
is, and the disagreement was load-bearing.

`3f9e7e8` added both together, and both gated on a **force flag**. `47f7b92` then changed
the hook to gate on a **dry run** instead, because a force flag does not mean deletion:
`git clean -fn` lists what it would remove and removes nothing, `-n` overriding `-f`.
That commit changed the hook body and the suite; it never revisited the globs, which kept
the force-flag reading. That is where the two mechanisms diverged, and neither the hook's
own tests nor the suite's `assert_deny_entry` calls could see it — the calls asserted that
the entries were *present*, and a comment above them said their glob semantics were out of
scope.

The globs are unfixable in place. A Claude Code `permissions.deny` pattern is a prefix
glob with no negation and no lookahead, so `Bash(git clean -f*)` also matches `-fn`,
`-fdn` and `-f --dry-run`, and `Bash(git clean *-f*)` also matches `-n -f`. Every one of
those is a preview. No narrowing exists: there is no prefix pattern matching `-fd` but not
`-fdn`. Enumerating the destructive bundles instead is unbounded — git accepts any order
within a bundle and any unambiguous abbreviation, so `--f` and `--fo` are `--force` too.

A `permissions.deny` match is also the one verdict an operator cannot approve in session.
So the previews were not merely inconvenient; they were permanently unreachable, which
pushes an operator inspecting a dirty tree toward running the destructive form to find out
what it would have done.

Against that, the globs never covered the forms the hook exists for. A `Bash(...)` prefix
pattern cannot reach `cd /tmp && git clean -fd`, `git -C /repo clean -fd`,
`sudo git clean -fdx`, `git submodule foreach git clean -fd`, or
`git -c clean.requireForce=false clean -d`. The hook blocks all of them.

The case for keeping the globs anyway was defence in depth against the hook going missing,
and until recently that had a concrete route: a private `settings.overlay.json` defining
`hooks.PreToolUse` replaced the base array wholesale, silently, while leaving
`permissions.deny` intact — so the globs really were the surviving layer.
[ADR 0043](0043-overlays-may-not-replace-a-base-array.md) closed that route. `install.sh`
now derives the base file's non-empty arrays at merge time and aborts the install rather
than deploying a settings file missing any of them. The premise of the defence-in-depth
argument no longer holds.

## Decision

**Remove both `git clean` deny globs. The `PreToolUse` hook is the sole mechanism guarding
`git clean`.**

Two mechanisms for one job was the defect, not the safety margin. They were added
together, only one was maintained, and the stale one was the one no test could evaluate.

What the surviving mechanism promises, stated so a later edit can be measured against it:
the hook blocks every `git clean` **it can see in the command text** that is not a dry run
— not merely the forced ones, so `git clean -d` and `git -c clean.requireForce=false clean`
are blocked too — it permits `-n`, `-i`, `--dry-run` and `--interactive` wherever they
appear in the argument list, and it fails closed when `jq` cannot read its input.

The qualification is load-bearing rather than decorative, and the Consequences below say
what it excludes. A promise of "every `git clean`" would be the wrong thing to measure a
later regex change against, because a narrowing that preserved it as literally written
would preserve nothing real.

## Consequences

- The previews come back. `git clean -fn`, `-nf`, `-fdn`, `-f -n`, `-n -f`,
  `-f --dry-run` and `-i -f` are usable again. `scripts/claude-settings-hooks-test.sh`
  asserts them, so the forms this record restores are the forms a future change has to
  keep restoring.
- **`git clean` becomes the only destructive command in this file guarded by a hook with
  no `permissions.deny` backstop.** The file now holds three shapes: `rm` keeps both
  layers (`Bash(rm -rf *)`, `Bash(rm -fr *)`, plus its own hook); `git reset --hard`,
  `git push --force`, `dd`, `mkfs` and `sudo` keep deny entries and have no hook; and
  `git clean` alone has a hook and nothing else. It is not the removal of the last
  restrictive deny surface — those remain — but it is the first destructive command here
  to rely on one layer.
- **Three residuals now have nothing behind them, and they are the price of the
  decision.** A future edit that breaks the hook's regex is the obvious one, and the suite
  catches it. The other two it does not. *Hook-execution failure:* Claude Code treats exit
  2 alone as blocking, so a hook that dies for a reason its body did not anticipate exits
  non-2 and the command proceeds — shadowing `grep` with a stub that exits 2 makes this
  hook exit 0 on `git clean -fd`. Only the `jq` branch is pinned fail-closed
  (`assert_fails_closed`); issue #139 owns closing the rest. *Text-matching evasion:* the
  hook reads the command as text, so a subcommand reached through a variable, a backtick
  or an alias is invisible to it — `C=clean; git $C -fd` is allowed. That is a limit of
  text matching rather than a defect to test away; the suite header records this class of
  accepted false negative and issue #113 owns stating it fully there.
- What replaces the glob is the suite, not nothing. `scripts/claude-settings-hooks-test.sh`
  executes the hook body against every destructive form named above and against the legal
  previews, and `just verify` runs it. That is a stronger guard against a bad hook edit
  than a glob which never matched a compounded command — but it guards the repository, not
  a deployed host, which is the honest limit of the trade.
- `assert_deny_entry` and its two calls are removed with them. Nothing in the suite
  asserts anything about `permissions.deny` any more; `install-test.sh` still asserts that
  whatever the base file holds arrives in the deployed file, which is unaffected by the
  list getting shorter.
- **A host whose `settings.json` was produced by a clobbering overlay before ADR 0043
  landed is worse off.** Such a deployment lost the hook and kept the deny array, so the
  globs were still refusing its plain `git clean -fd`; after this change nothing does,
  until the overlay is fixed and the install re-run. Issue #126 owns repairing an
  already-deployed settings file. This record does not lengthen that window, but it does
  empty it.
- Reversible at the price the record names: re-adding two array entries restores the old
  state, along with the unappealable previews.

## Considered & rejected

- **Keep both entries as defence in depth** (issue #111, option 2). Rejected on price,
  after correcting the premise on both sides. The keep-argument's premise — hooks vanish
  through an overlay — expired with ADR 0043, which aborts that install. But the
  counter-argument must not be overstated either: a deny entry is matched in-process
  against the parsed settings, while a hook is a subprocess whose non-2 exit is
  non-blocking, so the two do *not* fail together, and the entries really would still
  refuse an uncompounded `git clean -fd` in the fail-open case recorded above. The
  rejection therefore rests on price alone, which is enough: the entries cost every
  force-flagged preview, permanently and unappealably, and buy coverage only of the
  uncompounded form — not of `cd /tmp && git clean -fd`, `git -C`, `sudo`,
  `submodule foreach`, or any other shape the hook exists for. Issue #139 buys the same
  residual back by making the hook fail closed, which is the cheaper half of this trade.
- **Move both entries from `deny` to `ask`.** The `permissions` object is not deny-only,
  and an `ask` entry prompts rather than refusing, so this is the one settings-layer
  option that keeps a backstop without making the previews unreachable. Rejected on two
  grounds. It contradicts the decision recorded here — the operator asked for one
  mechanism, and an entry that fires ahead of the hook is a second one — and while the
  hook is healthy the entry fires *only* on previews, since every destructive form is
  already blocked before the operator sees a prompt. So it buys a backstop for the
  fail-open case at the cost of a prompt on every dry run, and #139 buys the same
  backstop for nothing.
  [ADR 0009](0009-native-permission-lists-grant-capabilities.md) frames
  `permissions.deny` as the checked-in restrictive surface and rejects adding permission
  fields for symmetry; this is consistent with that.
- **Narrow the globs to exclude dry runs.** Rejected as unavailable rather than unwanted:
  prefix globs have no negation, and no pattern matches `-fd` without also matching
  `-fdn`.
- **Enumerate the destructive bundles** — deny `-fd`, `-df`, `-fdx` and the rest.
  Rejected: bundle order is free and abbreviations are accepted, so the list is unbounded
  and the first form nobody thought of is allowed. Deciding this by parsing is what the
  hook already does.
- **Keep only `Bash(git clean *-f*)`.** Rejected as the worst of both: it is the broader
  of the two, so it keeps the largest set of false positives, while dropping the entry
  that at least matched the plain destructive prefix.
- **Do nothing and document the false positives.** Rejected: the documentation would say
  that the recommended way to inspect a tree before deleting from it is denied, and the
  operator cannot approve past a deny. Recording a defect an operator meets weekly is not
  a substitute for removing it.
