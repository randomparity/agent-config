# 0053 — The required check proves shell portability, not a matrix leg

## Status

Accepted (2026-08-10)

## Context

The two shipped Claude `PreToolUse` hook bodies must stay inside POSIX shell, because the
shell Claude Code runs a hook body in is not this repository's to choose.
`scripts/claude-settings-hooks-test.sh` proves that by re-running the bodies under `sh`.

Since #112 the suite resolves `sh` by what it accepts rather than by where `/bin/sh`
points, and where `sh` turns out to be an extended shell it prints a skip notice instead
of a green line it has not earned. The operator rejected raising the toolchain floor —
declaring `dash` a prerequisite — so on macOS and on the Fedora developer hosts the skip
is the intended outcome.

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
   empty leaves #112's behaviour byte-for-byte as shipped.
2. The `verify` job checks the repository out and runs that suite with
   `POSIX_ASSERTIONS_REQUIRED=1`.

Any non-empty value requires the assertions, rather than the literal `1`. A wiring that
says `true` and is silently ignored is the failure this record exists to prevent, and a
misspelling in the workflow must not be the difference between a gate and a no-op.

`verify` is the home because it is the one job in this workflow that the matrix cannot
reach. It already exists to keep a stable required-check context and already runs
unconditionally on `ubuntu-latest`; adding the proof there makes the guarantee independent
of which operating systems the matrix happens to list this year. The matrix legs are left
alone: the ubuntu leg still proves the property as a by-product and macOS still skips.

The consequence worth stating plainly is that dropping `ubuntu-latest` from the matrix no
longer *can* turn CI red, because it no longer removes the proving ground. Issue #136 asked
for red on that route; this answers the requirement behind it — the guarantee must not
disappear silently — by making the disappearance impossible rather than by detecting it.

`scripts/claude-settings-posix-guard-test.sh` exercises the refusal on every host and every
CI leg, since the guard's failure path is otherwise never taken anywhere.

## Consequences

- The required check now fails for a reason that has nothing to do with the matrix. That is
  the point, and it means `verify: suite matrix reported ...` is no longer the only way the
  job can go red.
- The hooks suite runs twice per CI run on Linux: once inside the ubuntu leg, once in
  `verify`. It takes seconds and needs no toolchain install, so the duplication is cheaper
  than any mechanism for reporting one job's internal verdict to another.
- `verify` gains a checkout and therefore executes contributor code on a fork pull request,
  where before it only compared a string. The `suite` job already does strictly more of
  this under the same `contents: read` permission and the same SHA-pinned checkout with
  `persist-credentials: false`, so the exposure is not new in kind.
- The step depends on the runner image providing `jq`. Its absence fails loudly on the first
  call rather than skipping, so the dependency cannot rot into a silent pass.
- `POSIX_ASSERTIONS_REQUIRED` is a new environment-variable contract on a tracked script.
  It is read at one place, documented there, and set in one place.
- `POSIX_ASSERTIONS_REQUIRED=0` requires the assertions, which reads backwards. Accepted:
  the alternative reading fails open, and this one fails closed.
- The property is still proven on Linux only. A hook body that is POSIX on dash but not on
  some other POSIX shell is not covered, and nothing here changes that.

## Considered & rejected

- **Set `POSIX_ASSERTIONS_REQUIRED=1` on the ubuntu matrix leg** — issue #136's option 1,
  and one line shorter. Rejected because the requirement then lives inside the thing that
  can be removed: deleting `ubuntu-latest` from the matrix deletes the guard with it, which
  is the first of the three routes the issue names and leaves the defect half-fixed.
- **Install dash as a CI prerequisite** — issue #136's option 2. Rejected: the operator
  rejected raising the toolchain floor when deciding #112, and this would reintroduce it for
  CI while also being the route that a future image change quietly undoes.
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
