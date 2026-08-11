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

That left the property proven in exactly one environment: the `ubuntu-latest` leg of
`.github/workflows/verify.yml`, whose `/bin/sh` is dash. Nothing fails if that stops being
true. Drop the leg, or ship an image with a different `/bin/sh`, or move the leg into a
container, and every leg skips, every leg exits 0, and the aggregating `verify` job — which
asserts only `needs.suite.result == success` — keeps reporting that every leg passed. The
suite's own comment named the ubuntu leg as the proving ground; that was a claim in a
comment with no enforcement behind it, and issue #136 is its removal.

## Decision

**The proving ground is the `verify` job, not a matrix leg, and it runs the suite in a mode
where the skip is refused.**

Two halves, which must land in the same change or the guard ships inert:

1. `scripts/claude-settings-hooks-test.sh` fails instead of skipping when
   `POSIX_ASSERTIONS_REQUIRED` holds a non-empty value and `sh` accepts bashisms. Unset or
   empty leaves #112's skip as shipped: same condition, same notice, same
   `posix_verdict`, same exit status.
2. The `verify` job checks the repository out and runs that suite with
   `POSIX_ASSERTIONS_REQUIRED=1`.

Any non-empty value requires the assertions, rather than the literal `1`. A wiring that
says `true` and is silently ignored is the failure this record exists to prevent.

`verify` is the home because it is the one job in this workflow the matrix cannot reach: it
already exists to keep a stable required-check context and already runs unconditionally on
`ubuntu-latest`. The matrix legs are left alone — the ubuntu leg still proves the property
as a by-product and macOS still skips.

Two sentences in the suite's POSIX region name the ubuntu leg as the sole proving ground
and point at #136 as open work. Both stop being true here, so both are corrected in the
same change. That is not a weakening of the skip: what the notice says changes, what it
does does not.

`scripts/claude-settings-posix-guard-test.sh` exercises the refusal on every host and every
CI leg, since the guard's failure path is otherwise never taken anywhere.

## Consequences

- The required check now fails for a reason that has nothing to do with the matrix. That is
  the point, and it means `verify: suite matrix reported ...` is no longer the only way the
  job can go red.
- **The designed failure blocks the whole repository, and its remedy is a decision nobody
  has taken yet.** When `ubuntu-latest` stops shipping dash as `/bin/sh` — an upstream
  change arriving without warning — `verify` reds on every open pull request, including
  ones touching nothing here. The intended response is to install a POSIX shell in that one
  step and point `sh` at it. That is the CI-only toolchain floor rejected below, and it is
  rejected as today's mechanism rather than forever: it costs nothing to skip while the
  image supplies dash, and if the image stops, the choice is forced and is the operator's.
  Relaxing or deleting the gate under a red required check is the outcome this bullet
  exists to prevent.
- The guarantee is two of five hook bodies, and behavioural rather than structural: a
  non-POSIX construct on a branch the chosen inputs do not reach is not detected. Issue
  #157 owns widening it.
- The hooks suite runs twice per CI run on Linux: once inside the ubuntu leg, once in
  `verify`. It takes seconds and needs no toolchain install, so the duplication is cheaper
  than any mechanism for reporting one job's internal verdict to another.
- `verify` gains a checkout and therefore executes contributor code on a fork pull request,
  where before it only compared a string. The `suite` job already does strictly more of
  this under the same `contents: read` permission and the same SHA-pinned checkout with
  `persist-credentials: false`, so the exposure is not new in kind.
- The step depends on the runner image providing `jq`. Its absence fails loudly on the first
  call rather than skipping, so the dependency cannot rot into a silent pass.
- `POSIX_ASSERTIONS_REQUIRED` is a new environment-variable contract on a tracked script,
  read at one place and set at one place. `POSIX_ASSERTIONS_REQUIRED=0` requires the
  assertions, which reads backwards; accepted, because the alternative reading fails open.

## Considered & rejected

- **Set `POSIX_ASSERTIONS_REQUIRED=1` on the ubuntu matrix leg** — issue #136's option 1,
  and one line shorter. Rejected because the requirement then lives inside the thing that
  can be removed: deleting `ubuntu-latest` from the matrix deletes the guard with it, which
  is the first of the three routes the issue names and leaves the defect half-fixed. This is
  also why dropping that leg can no longer turn CI red — the decision above answers the
  requirement behind that acceptance sentence, that the guarantee must not vanish silently,
  by making the vanishing impossible rather than by detecting it.
- **Install dash as a CI prerequisite** — issue #136's option 2. Rejected as the mechanism:
  the operator rejected raising the toolchain floor when deciding #112, and an installed
  package is exactly what a future image change quietly undoes. Kept as the remedy if the
  image ever drifts, per the Consequences bullet above.
- **Check the extracted bodies statically with `shellcheck -s sh` instead.** Genuinely
  simpler and broader: `shellcheck` is already a prerequisite, all five bodies pass it
  today, `[[ ]]` is reported as SC3010, and the check can never skip because it does not
  care what `sh` resolves to — no environment variable, no second checkout, no dependence
  on the runner image. Rejected as a replacement because it proves a different property:
  that the bodies contain no non-POSIX construct, not that they still exit 0 and 2 for the
  right inputs under a real POSIX shell, which is what #112's assertions establish and what
  would still skip everywhere. It is the right addition rather than the right substitution,
  and it is issue #157.
- **Have the legs report to `verify`, by artifact or job output, and fail when no leg
  proved.** The only shape that literally turns "matrix leg dropped" red. Rejected as more
  machinery than the guarantee costs: matrix job outputs are last-writer-wins and so cannot
  distinguish "a leg proved it" from "the last leg to finish did not", and the artifact
  version adds an upload step per leg plus a download-and-count step to buy a signal that
  running the suite directly in `verify` provides outright.
- **Parse the suite's log line from the aggregating job.** Rejected: it makes a green build
  depend on the exact wording of a `printf`, and the wording is prose that a later change is
  entitled to improve.
- **Assert in `verify` only that this runner's `sh` rejects bashisms**, without running the
  suite. Cheaper, and it catches image drift. Rejected because it proves an environment
  exists rather than that the hook bodies pass in it, so a hook body that acquired a bashism
  would still ship green wherever the matrix no longer covered it.
- **Do nothing.** Rejected: nothing regressed at #112, but the guarantee is single-legged
  and its loss is silent, and a guarantee nobody is told they have lost is one they do not
  have.
