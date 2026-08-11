# 0056 — A guard that cannot evaluate its input refuses

## Status

Accepted (2026-08-10)

## Context

The five `PreToolUse` hooks in `agents/claude/shared/settings.base.json` decide whether a
Bash command runs. Each is one shell expression that shells out to helpers — `jq` to read
the tool input, `grep` to match the command text, and in the masked-exit guard `awk` to
extract a substring.

Claude Code blocks on **exit 2 alone**. Every other non-zero status from a `PreToolUse`
hook is a non-blocking error: it is surfaced, and the tool call proceeds. A hook that dies
for a reason its body did not anticipate therefore does not refuse the command — it permits
it, which is the opposite of what a guard is for.

The same shape reached the input itself. `jq -r '.tool_input.command'` prints the string
`null` and exits 0 when the field is absent, so a payload carrying no command left every
guard matching its patterns against the literal text `null` — no match, exit 0, call
permitted. A guard that never saw a command was answering as though it had seen a harmless
one.

Only one helper failure was handled. The `git clean` guard has checked `jq`'s exit status
since it was written; nothing else checked anything. `grep` exits 1 for "no match" and 2 or
more for an error, so the two are distinguishable, but a bare `if … | grep -q …; then` reads
both as "no match" and falls past the `exit 2`. Measured against the shipped bodies, with a
`grep` on `PATH` that exits 2, **all five hooks exited 0** — including the destructive guard
on a real `git clean -fd`. With `jq` unavailable, four of the five exited 0; only the
`git clean` guard refused.

The same class had just produced a live false green elsewhere in this repository:
`scripts/check-public-safety.sh` used a bare `if rg …`, and ripgrep's exit 2 on an unreadable
path read as "no match", so the secret scanner reported clean while printing the secret.

`permissions.deny` carries `Bash(git clean -f*)` and `Bash(git clean *-f*)`, matched in
process and not dependent on any hook. That is a partial backstop only: a `Bash(...)` prefix
glob cannot reach `cd /tmp && git clean -fd`, `git -C /repo clean -fd`, `sudo git clean -fdx`
or `git submodule foreach git clean -fd`, all of which the hook is the only thing blocking.

## Decision

**A hook that cannot evaluate its input exits 2 with a `BLOCKED:` message naming the helper
that failed.** All five hooks capture the helper's status rather than testing the helper
directly in an `if`, and treat any status that is not a clean answer as a refusal:

```sh
hgrep() { printf '%s\n' "$1" | grep -qE "$2"; s=$?
  if [ "$s" -gt 1 ]; then echo "BLOCKED: … (grep exited $s) …" >&2; exit 2; fi
  return "$s"; }
```

Status 0 is a match, 1 is a no-match, and anything above is a fault. `jq` is guarded by
`CMD=$(jq -r …) || { … exit 2; }` in every hook, as the `git clean` guard already did.

**Uniform, including the advisory hooks.** The obvious objection is that failing closed on
the `rg -r` or masked-exit guard blocks ordinary work when a helper breaks. It does not,
because the five hooks run on the **same** Bash tool call and one exit 2 blocks it. The
`git clean` guard has failed closed on `jq` since it was written, so on a broken `jq` the
call was already refused whatever the other four returned; the same now holds for `grep`.
There is no command that uniform fail-closed blocks and selective fail-closed allows. What
changes is which diagnostic prints — the guard that actually could not evaluate says so,
instead of the user seeing a message about `git clean` after typing `rg -r`. Four hooks
whose silence is safe only because of a fifth hook's behaviour, stated nowhere, is the
coupling this record removes.

**`awk` is checked where its answer is read, not before.** The masked-exit guard used `awk`
to extract the text preceding `just ci` on every Bash call, though exactly one test reads
that text: the `set -o pipefail` exemption. The call now sits inside the branch that has
already matched a masking pattern, and a broken `awk` refuses there, naming `awk`. Placement
is the decision, not whether to check: guarding `awk` where it used to sit would refuse every
command, including the overwhelming majority that match no masking pattern and never read the
result. Lazy placement refuses exactly the command shapes an unguarded broken `awk` already
refused — `set -o pipefail; just ci | tail` loses its exemption either way — and changes only
the diagnostic. A command matching no masking pattern no longer runs `awk` at all.

`printf` and `echo` are shell builtins in every shell these bodies run under, so a `PATH`
entry of either name is never reached. The suite asserts this rather than assuming it, which
is what makes the helper list — `jq`, `grep`, `awk` — a checked claim.

**One path still returns 0 without evaluating the command, and its degraded behaviour is
split.** The push-to-main guard exits 0 when `GT_REFINERY=1` — an explicit operator opt-out
for that one guard. The check sits where it sits in the base revision: *after* the `jq`
capture and *before* the `grep`. Guarding `jq` therefore gives the hatch two different
answers under a broken helper. A broken `jq` refuses even with `GT_REFINERY=1`, because the
capture runs first; a broken `grep` is never reached, so the hatch still permits.

That split is a consequence of statement order rather than a designed boundary, and this
record does not reorder the check — moving it would change what the escape hatch means, which
is a separate decision from the one here. It is stated and asserted instead, so the next
reader finds it recorded rather than discovering it. Either way the block holds: the other
four hooks refuse the same tool call on helper failure, so `GT_REFINERY=1` suppresses one
guard's verdict, never the refusal.

**Unreadable input is treated as unreadable, not as an empty command.** `jq -r` prints the
string `null` for an absent field and exits 0, so each guard was matching its patterns
against the literal text `null`, finding nothing, and permitting the call — a payload with no
`command` field, no `tool_input`, or empty stdin was allowed by all five. The capture uses
`jq -er`, whose non-zero status on a null result the existing `||` branch already handles.
Malformed JSON was never affected: `jq` fails to parse and the branch fires. A command that is
genuinely the empty string still reads as a command and is still allowed, since it runs
nothing.

## Consequences

A broken or absent `jq` or `grep` now blocks every Bash tool call, with five diagnostics
instead of one. That was already true for `jq` via the `git clean` guard; the change makes it
true for `grep` and makes the reason legible.

The recovery is not reachable from the tool being refused, and the messages say so. Repairing
`PATH` is itself a Bash command, so an agent that has hit this cannot fix it: the block is
total until a human repairs the helper outside the session. That is the correct end state for
a guard that cannot evaluate anything — the alternative is a bypass flag, which is the hole
under another name — but it is a hard stop rather than a degraded mode, and the messages name
the helper precisely so the human has something to act on.

The hook bodies grow a function definition each and stay POSIX shell, which
`scripts/claude-settings-hooks-test.sh` proves under a `sh` that rejects bashisms.

`scripts/claude-settings-hooks-test.sh` gains a helper-failure matrix: one stub directory per
helper, each stub exiting 2, plus a `jq` stub exiting 127 so "uninstalled" and "broken" are
distinct cases. It also gains an enumeration-free assertion — run the body with an empty
`PATH`, so every external command fails including one added later — and first assertions for
the `rm -rf`, push-to-main and `rg -r` guards, which previously had none at all. Each
fail-closed assertion is paired with the triggering and benign commands that make it bite; a
fail-closed assertion alone would pass against a hook that blocks everything.

None of this widens what the guards match. The matching behaviour with every helper healthy
is unchanged, command for command.

## Considered & rejected

**Fix only the `git clean` guard**, the minimum issue #139 asks for. Rejected: the defect is
a shell idiom, not a line, and it was present in all five hooks. Fixing one leaves four
identical instances of the same bug for the next reader to rediscover — and the masked-exit
guard's whole purpose is stopping a red gate from reading as green, which a silently absent
guard reintroduces.

**Fail closed on the destructive guards only** (`rm -rf`, `git clean`), leaving the three
advisory hooks fail-open. Rejected on evidence rather than principle: the cost that would
justify the split does not exist, since one guard already blocks the shared tool call. The
split would buy a worse diagnostic and a hidden dependency between hooks.

**Guard `awk` where the call already sat**, ahead of the `if`, alongside the `jq` check.
Rejected: the extraction runs on every Bash call but is read only in the pipefail-exemption
branch, so a check there would refuse every command to protect one branch. Moving the call
into that branch and checking it there gets the diagnostic without the blocking, which is
what the Decision adopts. Leaving `awk` unchecked entirely was also rejected, though it is
not unsafe: the branch already fails closed, so the cost was a message naming nothing.

**Assert the fail-closed floor against the five hooks by name.** Rejected: the suite reaches
a hook through a string in its own block message, so a sixth hook is simply absent and its
absence is not a failure — the gate would go green on a newly reintroduced defect. The floor
is asserted by enumerating the `PreToolUse` array instead, with a count assertion under it so
an enumeration that matches nothing cannot pass as an enumeration that found no problem.

**Assert that floor with an empty `PATH` alone.** Rejected as insufficient once written: with
no `PATH` the *first* helper a body reaches fails, which for all five is the `jq` call that
reads the tool input. A hook that guarded `jq` and nothing else would satisfy it while still
failing open on `grep` — issue #139's defect exactly. The enumeration runs the broken-`jq` and
broken-`grep` stubs over every body as well, and the empty-`PATH` case is kept as what it
honestly is: a floor covering the helper reached first, including one nobody stubbed.

**Treat `grep`'s status ≥ 2 as a no-match and carry on**, on the grounds that a guard should
not stop work it cannot justify stopping. Rejected: that is the current behaviour and it is
the defect. A destructive-operation guard that cannot read the command has no basis for
believing the command is safe.

**Rely on `permissions.deny`.** Rejected: those entries are prefix globs over the simple
uncompounded command and cannot reach a compounded, wrapped, or `-C`-qualified `git clean`.
Issue #111 proposed removing them and was closed won't-fix, so they remain — as a backstop,
not as cover for a guard that fails open.
