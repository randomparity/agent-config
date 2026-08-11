# 0053 — The required check proves shell portability, not a matrix leg

## Status

Accepted (2026-08-10)

## Context

The shipped Claude `PreToolUse` hook bodies must stay inside POSIX shell, because the shell
Claude Code runs a hook body in is not this repository's to choose.
`scripts/claude-settings-hooks-test.sh` proves that by re-running bodies under `sh` and
comparing exit statuses. It covers two of the five bodies
`agents/claude/shared/settings.base.json` ships — the `git clean` guard and the masked-exit
guard — which is the extent of the guarantee below; widening it is issue #157.

Since #112 the suite resolves `sh` by what it accepts rather than by where `/bin/sh`
points, and where `sh` turns out to be an extended shell it prints a skip notice instead of
a green line it has not earned. The operator rejected raising the toolchain floor —
declaring `dash` a prerequisite — so on macOS and on the Fedora developer hosts the skip is
the intended outcome.

That leaves the property proven in exactly one environment: the `ubuntu-latest` leg of
`.github/workflows/verify.yml`, whose `/bin/sh` is dash. Issue #136 enumerates the three
ways that stops being true; in each of them every leg skips, every leg exits 0, and the
aggregating `verify` job — which asserts only `needs.suite.result == success` — keeps
reporting that every leg passed. The suite's own comment named the ubuntu leg as the
proving ground: a claim in a comment with no enforcement behind it.

## Decision

**The proving ground is the `verify` job, not a matrix leg, and it runs the suite in a mode
where the skip is refused.**

Two halves, which must land in the same change or the guard ships inert:

1. `scripts/claude-settings-hooks-test.sh` refuses the skip when `POSIX_ASSERTIONS_REQUIRED`
   is set and `sh` accepts bashisms. Unset or empty leaves #112's skip as shipped: same
   condition, same notice, same `posix_verdict`, same exit status.
2. The `verify` job checks the repository out and runs that suite with
   `POSIX_ASSERTIONS_REQUIRED=1`.

The variable takes `1` or nothing, and is validated before the skip predicate is consulted
so an unrecognised value reds on every host whatever `sh` turns out to be. A gate that
reads as wired and is not is the failure this record exists to prevent, and it arrives as
readily by `true` being ignored as by `0` meaning its opposite.

`verify` is the home because it is the one job in this workflow the matrix cannot reach: it
already exists to keep a stable required-check context and already runs unconditionally on
`ubuntu-latest`. The matrix legs are left alone — the ubuntu leg still proves the property
as a by-product and macOS still skips.

The bound is deliberate. Removed are the routes that take the proving ground away as a side
effect of an unrelated decision — the leg dropped from the matrix, the leg moved into a
container — and image drift becomes a red build. Deleting the step or its `env:` line is
not defended against: it returns the suite to the skip branch and a green log, and
`verify.runs-on` is now load-bearing in the way `matrix.os` was.

Two sentences in the suite's POSIX region name the ubuntu leg as the sole proving ground
and point at #136 as open work. Both stop being true here, so both are corrected in the
same change. What the notice says changes; what it does does not.

## Consequences

- The required check now fails for a reason that has nothing to do with the matrix, so
  `verify: suite matrix reported ...` is no longer the only way the job can go red.
- **The designed failure blocks the whole repository, and its remedy is a decision nobody
  has taken yet.** When `ubuntu-latest` stops shipping dash as `/bin/sh` — an upstream
  change arriving without warning — `verify` reds on every open pull request, including
  ones touching nothing here. The intended response is to install a POSIX shell in that one
  step and point `sh` at it: the CI-only toolchain floor rejected below, rejected as today's
  mechanism rather than forever. It costs nothing to skip while the image supplies dash, and
  if the image stops, the choice is forced and is the operator's. Relaxing or deleting the
  gate under a red required check is the outcome this bullet exists to prevent.
- **ADR 0039's "added to the recipe, never to the hook" is amended here for a CI-only gate.**
  Every required-check assertion about repository content was reachable through `just ci`
  until now; this one is not, and cannot be — folding it into `just ci` would red on every
  developer host, which is what #112 settled against. The concrete loss is that
  `scripts/verify-push.sh` rehearses CI by running `just ci` in a disposable worktree, so
  from here a contributor can pass every local gate and the pre-push rehearsal and still red
  the required check. A `just` recipe would not close that: `just` is not installed on the
  `verify` runner, and a recipe reproducing the gate would fail by design on every host but a
  POSIX-`sh` one.
- The guarantee is two of five hook bodies, and behavioural rather than structural: a
  non-POSIX construct on a branch the chosen inputs do not reach is not detected. Issue
  #157 owns widening it.
- The hooks suite runs twice per CI run on Linux, once in the ubuntu leg and once in
  `verify`. It takes seconds and needs no toolchain install, so the duplication is cheaper
  than any mechanism for reporting one job's internal verdict to another.
- `verify` gains a checkout and therefore executes contributor code on a fork pull request,
  where before it only compared a string. The `suite` job already does strictly more of this
  under the same `contents: read` permission and the same SHA-pinned checkout with
  `persist-credentials: false`, so the exposure is not new in kind.
- The step depends on the runner image providing `jq`. Its absence fails loudly on the first
  call rather than skipping, so the dependency cannot rot into a silent pass.

## Considered & rejected

- **Set `POSIX_ASSERTIONS_REQUIRED=1` on the ubuntu matrix leg** — issue #136's option 1,
  and one line shorter. Rejected because the requirement then lives inside the thing that
  can be removed: deleting `ubuntu-latest` from the matrix deletes the guard with it, which
  is the first route the issue names and leaves the defect half-fixed. This is also why
  dropping that leg can no longer turn CI red — the decision answers the requirement behind
  that acceptance sentence, that the loss must not be silent, by removing the route rather
  than detecting it.
- **Install dash as a CI prerequisite** — issue #136's option 2. Rejected as the mechanism:
  the operator rejected raising the toolchain floor at #112, and an installed package is
  what a future image change quietly undoes. Kept as the remedy if the image drifts.
- **Check the extracted bodies statically with `shellcheck -s sh` instead.** Simpler,
  broader and unskippable, but it proves the bodies contain no non-POSIX construct rather
  than that they still exit 0 and 2 for the right inputs under a real POSIX shell. The right
  addition, not the right substitution: issue #157. Nor a reason to wait for it — #157 is
  unscheduled, and the guarantee that exists today is the one that can be lost today.
- **Require the assertions only on push to `main` or on a schedule**, leaving pull requests
  to the matrix leg. It bounds the blast radius above — an upstream image change would stop
  merges rather than blocking every open pull request — and it still fails loudly. Rejected
  because it detects drift after merge, and because a pull request adding a bashism to a hook
  body would then be caught only by the matrix leg, which is the thing that can go away.
- **Report a leg's verdict to the aggregating job**, by artifact or job output, and fail
  when no leg proved. The only shape that literally turns "matrix leg dropped" red. Rejected
  as more machinery than the guarantee costs: matrix job outputs are last-writer-wins and
  cannot distinguish "a leg proved it" from "the last leg to finish did not", and the
  artifact version buys with an upload per leg and a download-and-count what running the
  suite in `verify` provides outright.
- **Parse the suite's log line from the aggregating job.** Rejected: it makes a green build
  depend on the exact wording of a `printf`, which a later change is entitled to improve.
- **Assert in `verify` that this runner's `sh` rejects bashisms, then run the suite
  unmodified.** The cheapest option that still delivers both halves, and it drops the
  environment variable, its grammar, and the guard suite that exists only to exercise the
  refusal. Rejected because the workflow would then carry its own copy of the "is this `sh`
  POSIX" predicate the suite implements: the two can drift, and the drift is silent in the
  direction that matters — a workflow predicate that passes while the suite's stricter one
  still skips restores exactly the green-log skip #136 opened against. Refusing the skip
  inside the suite keeps one predicate, and asserts the thing that actually matters, which is
  that the assertions ran.
- **Do nothing.** Rejected: nothing regressed at #112, but a single-legged guarantee whose
  loss is silent is one nobody is told they have lost. The narrowness conceded above is an
  argument for #157, not for leaving the remaining guarantee undefended.
