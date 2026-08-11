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

**`awk` is deliberately not guarded**, and this is the one place the rule does not apply
mechanically. The masked-exit guard uses `awk` to extract the text preceding `just ci`, and
exactly one test reads that text: the `set -o pipefail` exemption. A broken `awk` empties it,
the exemption is lost, and `set -o pipefail; just ci | tail` is **blocked** — already failing
closed, in the only branch whose answer `awk` affects. A command matching no masking pattern
is untouched, because nothing reads the empty text. Guarding `awk` explicitly would convert a
false positive on one command shape into a block on every command, with no hole closed.

`printf` and `echo` are shell builtins in every shell these bodies run under, so a `PATH`
entry of either name is never reached. The suite asserts this rather than assuming it, which
is what makes the helper list — `jq`, `grep`, `awk` — a checked claim.

## Consequences

A broken or absent `jq` or `grep` now blocks every Bash tool call, with five diagnostics
instead of one. That was already true for `jq` via the `git clean` guard; the change makes it
true for `grep` and makes the reason legible. The recovery is stated in each message: repair
the helper on `PATH`.

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

**Guard `awk` the same way as `grep`.** Rejected: see the Decision. It is the one helper
whose failure already produces a refusal in the only branch that reads its output, so the
rule would add blocking without closing anything.

**Treat `grep`'s status ≥ 2 as a no-match and carry on**, on the grounds that a guard should
not stop work it cannot justify stopping. Rejected: that is the current behaviour and it is
the defect. A destructive-operation guard that cannot read the command has no basis for
believing the command is safe.

**Rely on `permissions.deny`.** Rejected: those entries are prefix globs over the simple
uncompounded command and cannot reach a compounded, wrapped, or `-C`-qualified `git clean`.
Issue #111 proposed removing them and was closed won't-fix, so they remain — as a backstop,
not as cover for a guard that fails open.
