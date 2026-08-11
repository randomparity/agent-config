# 0053 — The required check proves shell portability, not a matrix leg

## Status

Accepted (2026-08-10)

## Context

The shipped Claude `PreToolUse` hook bodies must stay inside POSIX shell, because the shell
Claude Code runs a hook body in is not this repository's to choose.
`scripts/claude-settings-hooks-test.sh` proves that by re-running bodies under `sh` and
comparing exit statuses — two of the five bodies
`agents/claude/shared/settings.base.json` ships, which is the extent of the guarantee
below; widening it is issue #157.

Since #112 the suite resolves `sh` by what it accepts rather than by where `/bin/sh` points,
and where `sh` is an extended shell it prints a skip notice instead of a green line it has
not earned. The operator rejected declaring `dash` a prerequisite on developer hosts, so
there and on macOS the skip is the intended outcome.

That leaves the property proven in exactly one environment: the `ubuntu-latest` leg of
`.github/workflows/verify.yml`, whose `/bin/sh` is dash. Issue #136 enumerates the three
ways that stops being true. In each, every leg skips, every leg exits 0, and the aggregating
`verify` job — which asserts only `needs.suite.result == success` — keeps reporting that
every leg passed. The suite's own comment named the ubuntu leg as the proving ground: a
claim with no enforcement behind it.

## Decision

**The proving ground is the `verify` job, not a matrix leg, and it runs the suite in a mode
where the skip is refused.** `scripts/claude-settings-hooks-test.sh` gains a
`POSIX_ASSERTIONS_REQUIRED` variable that turns the skip into a failure, and the `verify`
job checks the repository out and runs the suite with it set. Both halves land together or
the guard ships inert. The variable takes `1` or nothing and is validated before the skip
predicate is consulted, so a workflow that says `true` reds on every host rather than
sitting green until the day the gate is needed. Unset or empty leaves #112's skip as
shipped: same condition, same notice, same verdict line, same exit status.

The matrix legs are left alone: the ubuntu leg still proves the property as a by-product and
macOS still skips. Two sentences in the suite's POSIX region name that leg as the sole
proving ground and point at #136 as open work; both stop being true here and are corrected
in the same change, without touching what the skip does.

The delta against putting the same variable on the ubuntu leg is narrower than it looks,
and stating it honestly is the point of the record. On that leg the variable travels with
the step, so image drift and a move into a container both red there too. What only this
placement survives is the leg being dropped from the matrix, and the general case behind it:
the guarantee stops depending on which operating systems the matrix lists.

Against a missing or mistyped `env:` key nothing on a dash runner can help — a wired gate and
an inert one produce identical output there, and diverge only on the day the gate is needed.
So the wiring itself is asserted from the repository side:
`scripts/claude-settings-posix-guard-test.sh` fails when `.github/workflows/verify.yml` stops
setting `POSIX_ASSERTIONS_REQUIRED` to `1`, which is also what defends the step against
deletion. `verify.runs-on` remains load-bearing in the way `matrix.os` was, fail-closed.

Because the refusal is the message an operator meets at an unknown future date, it must name
the variable, the shell that failed the test, and the two ways out: give that step a POSIX
`sh`, or fix the hook bodies. A refusal that reports only what did not happen leaves the
operator to rediscover this record.

## Consequences

- The required check now fails for a reason that has nothing to do with the matrix, so
  `verify: suite matrix reported ...` is no longer the only way the job can go red.
- **The designed failure blocks the whole repository, and its remedy is a decision nobody
  has taken yet.** When `ubuntu-latest` stops shipping dash as `/bin/sh` — an upstream change
  arriving without warning — `verify` reds on every open pull request, including ones
  touching nothing here. The intended response is to install a POSIX shell in that one step
  and point `sh` at it, which is the open operator call below. Relaxing or deleting the gate
  under a red required check is the outcome this bullet exists to prevent.
- **The gate is not reachable through `just ci`.** Every required-check assertion about
  repository content was until now, and `scripts/verify-push.sh` rehearses CI by running
  `just ci` in a disposable worktree — so from here a contributor can pass every local gate
  and the pre-push rehearsal and still red the required check. Folding the assertion into
  `just ci` would red on every developer host, which is what #112 settled against, and a
  `just` recipe would not help: `just` is not installed on the `verify` runner. ADR 0039's
  claims survive intact; what changes is that `just ci` is no longer the whole of CI.
- The guarantee is two of five hook bodies, and behavioural rather than structural: a
  non-POSIX construct on a branch the chosen inputs do not reach is not detected. Issue #157
  owns widening it.
- The hooks suite runs twice per CI run on Linux, once in the ubuntu leg and once in
  `verify`. It takes seconds and needs no toolchain install.
- `verify` gains a checkout and therefore executes contributor code on a fork pull request,
  where before it only compared a string. On a completed run the `suite` job already does
  strictly more of this, so the exposure is not new in kind; on a cancelled one it may have
  done nothing, since `if: always()` includes cancellation and `verify` starts anyway. What
  bounds it in both cases is the same: `contents: read`, no secrets, and a SHA-pinned
  checkout with `persist-credentials: false`.
- **The requirement is a predicate over `sh`, not over the assertions.** Refusing the skip
  proves the environment can prove the property; it does not prove any assertion still
  exists. Delete the four `assert_posix_agrees` calls and the verify runner's `sh` is still
  dash, the requirement is still met, and the suite still reports the assertions as having
  run. That is the ordinary exposure of deleting a test, not a route this gate is shaped to
  close, and buying a source-text assertion over the suite's own body would trade it for
  false reds on every refactor.
- The step depends on the runner image providing `jq`. Its absence fails loudly on the first
  call rather than skipping, so the dependency cannot rot into a silent pass.

## Considered & rejected

Two entries below are deferrals rather than refusals, and are marked as such: both questions
are live and owned elsewhere, and neither is settled by this record.

- **Set `POSIX_ASSERTIONS_REQUIRED=1` on the ubuntu matrix leg** — issue #136's option 1,
  and one line shorter. Rejected because the requirement then lives inside the thing that can
  be removed: deleting `ubuntu-latest` from the matrix deletes the guard with it. This is why
  dropping that leg can no longer turn CI red — the decision answers the requirement behind
  that acceptance sentence, that the loss must not be silent, by removing the route rather
  than detecting it.
- **Install dash in the CI job** — issue #136's option 2. *Deferred, not rejected.* Not
  decided here: #136 records the developer-host rejection at #112 and says in terms that
  "whether it is also rejected for CI alone is a separate call". It is an operator call,
  outside this change's scope, and it is the remedy named above if the image ever drifts.
- **Check the extracted bodies statically with `shellcheck -s sh`.** *Deferred, not
  rejected.* Simpler, broader and unskippable, but it proves the bodies contain no non-POSIX
  construct rather than that they still exit 0 and 2 for the right inputs under a real POSIX
  shell — an addition rather than a substitution, owned by issue #157. Nor a reason to wait
  for it: #157 is unscheduled, and the guarantee that exists today is the one that can be
  lost today.
- **Require the assertions only on push to `main` or on a schedule**, leaving pull requests
  to the matrix leg. It bounds the blast radius above and still fails loudly. Rejected because
  it detects drift after merge, and because a pull request adding a bashism to a hook body
  would then be caught only by the matrix leg, which is the thing that can go away.
- **Report a leg's verdict to the aggregating job** — by artifact, job output, or by parsing
  the suite's log line — and fail when no leg proved. The only shape that literally turns
  "matrix leg dropped" red. Rejected as more machinery than the guarantee costs: matrix job
  outputs are last-writer-wins and cannot distinguish "a leg proved it" from "the last leg to
  finish did not"; the artifact version buys with an upload per leg and a download-and-count
  what running the suite in `verify` provides outright; and the log-line version makes a green
  build depend on the wording of a `printf`.
- **Assert in `verify` that this runner's `sh` rejects bashisms, then run the suite
  unmodified.** The cheapest option that still delivers both halves, and it drops the
  environment variable and the guard suite that exercises the refusal. Rejected because the
  workflow would carry its own copy of the "is this `sh` POSIX" predicate the suite
  implements: the two can drift, and silently in the direction that matters — a workflow
  predicate that passes while the suite's stricter one still skips restores exactly the
  green-log skip #136 opened against.
- **Do nothing.** Doing nothing costs nothing: no repo-wide red when the image drifts, no
  contributor-code checkout in the required check, no second suite run — and what is defended
  is four behavioural assertions over two of five bodies. Rejected anyway, because that is a
  bounded, loud, fixable failure with a known remedy weighed against a silent one with none,
  and a guarantee nobody is told they have lost is one they do not have.
